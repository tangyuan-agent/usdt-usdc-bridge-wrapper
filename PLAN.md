# Circle CCTP Bridge Wrapper - Implementation Plan

## 背景

参考现有的 `L0BridgeWrapper`（LayerZero OFT wrapper），为 Circle 的 CCTP（Cross-Chain Transfer Protocol）创建一个类似的 wrapper 合约，简化 USDC 跨链转账流程。

### Circle CCTP 原生流程
1. **源链操作**:
   - 用户 approve USDC 给 TokenMessenger
   - 调用 `depositForBurn(amount, destinationDomain, mintRecipient, burnToken)`
   - 获得 messageHash（用于追踪）
2. **等待 attestation**:
   - Circle 的 attestation service 监听 burn 事件
   - 签名后生成 attestation（需要几分钟）
3. **目标链操作**:
   - 用户/relayer 调用 `receiveMessage(message, attestation)`
   - 在目标链 mint USDC 给接收者

### 现有 wrapper 的设计特点
- **UUPS 可升级**: 使用 OpenZeppelin 的 UUPS 代理模式
- **一键桥接**: 把多步操作合并为单个 `bridge()` 调用
- **自动手续费处理**: 内置 quote + 退款逻辑
- **5% 滑点保护**: 默认最小接收量
- **Max approval**: 初始化时对底层协议 max approve

---

## 设计目标

### 核心功能
创建 `CCTPBridgeWrapper` 合约，提供：
```solidity
function bridge(
    uint256 amount,
    uint32 destinationDomain,
    address recipient,
    address relayerAddress  // 可选，用于支付目标链 gas
) external payable returns (bytes32 messageHash);
```

### 优化点
1. **简化用户体验**: 
   - 用户只需调用一次 `bridge()`
   - 无需手动 approve（wrapper 内部处理）
   - 无需关心 attestation（通过 relayer 或前端自动处理）

2. **Gas 优化**:
   - Max approve USDC 一次（初始化时）
   - 缓存 TokenMessenger/MessageTransmitter 地址

3. **费用处理**:
   - 如果 `relayerAddress != address(0)`，支持用户在源链支付 relayer 费用
   - 自动退还多余的 native token

4. **可升级性**:
   - 使用 UUPS 代理，方便后续添加新链支持或修复 bug

---

## 技术架构

### 合约结构

```
CCTPBridgeWrapper (UUPS)
├── Initializable
├── UUPSUpgradeable
├── OwnableUpgradeable
└── ReentrancyGuardUpgradeable  // 防止重入攻击
```

### 核心依赖
```solidity
interface ITokenMessenger {
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken
    ) external returns (uint64 nonce);
}

interface IMessageTransmitter {
    // 用于目标链接收消息（可选，如果 wrapper 也部署在目标链）
    function receiveMessage(
        bytes calldata message,
        bytes calldata attestation
    ) external returns (bool success);
}
```

### 状态变量
```solidity
contract CCTPBridgeWrapper {
    ITokenMessenger public tokenMessenger;
    IERC20 public usdc;
    
    // Relayer fee (basis points, e.g., 10 = 0.1%)
    uint256 public relayerFeeBps;
    address public feeCollector;
    
    // Domain ID mapping (for validation)
    mapping(uint32 => bool) public supportedDomains;
    
    event BridgeInitiated(
        bytes32 indexed messageHash,
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        uint32 destinationDomain
    );
}
```

---

## 实现步骤

### Phase 1: 基础合约（MVP）
**预期时间**: 2-3 小时

1. **合约骨架**:
   - 创建 `CCTPBridgeWrapper.sol`
   - 继承 UUPS + Ownable + ReentrancyGuard
   - 添加 `ITokenMessenger` 和 `IERC20` 接口

2. **Initialize 函数**:
   ```solidity
   function initialize(
       address _tokenMessenger,
       address _usdc,
       address _owner
   ) external initializer {
       __Ownable_init(_owner);
       tokenMessenger = ITokenMessenger(_tokenMessenger);
       usdc = IERC20(_usdc);
       usdc.approve(_tokenMessenger, type(uint256).max);
   }
   ```

3. **Bridge 函数（简化版）**:
   ```solidity
   function bridge(
       uint256 amount,
       uint32 destinationDomain,
       address recipient
   ) external nonReentrant returns (bytes32 messageHash) {
       // 1. Transfer USDC from user
       usdc.transferFrom(msg.sender, address(this), amount);
       
       // 2. Call depositForBurn
       bytes32 mintRecipient = bytes32(uint256(uint160(recipient)));
       uint64 nonce = tokenMessenger.depositForBurn(
           amount,
           destinationDomain,
           mintRecipient,
           address(usdc)
       );
       
       // 3. Generate messageHash for tracking
       // (需要根据 CCTP 规范计算，通常是 keccak256(domain, nonce, ...))
       messageHash = keccak256(abi.encodePacked(block.chainid, nonce));
       
       emit BridgeInitiated(messageHash, msg.sender, recipient, amount, destinationDomain);
   }
   ```

4. **部署脚本**:
   - `script/DeployCCTP.s.sol`
   - 使用 UUPS proxy pattern
   - 支持多链部署（Ethereum, Arbitrum, Base, Polygon 等）

### Phase 2: 手续费与 Relayer 集成
**预期时间**: 2-3 小时

1. **Relayer 费用扣除**:
   ```solidity
   function bridge(
       uint256 amount,
       uint32 destinationDomain,
       address recipient,
       address relayerAddress
   ) external payable nonReentrant returns (bytes32 messageHash) {
       uint256 netAmount = amount;
       
       // Deduct relayer fee if provided
       if (relayerAddress != address(0)) {
           uint256 fee = (amount * relayerFeeBps) / 10000;
           netAmount = amount - fee;
           usdc.transfer(feeCollector, fee);
       }
       
       // ... rest of bridge logic
   }
   ```

2. **费用配置函数** (Owner only):
   ```solidity
   function setRelayerFee(uint256 _bps) external onlyOwner {
       require(_bps <= 100, "Fee too high"); // Max 1%
       relayerFeeBps = _bps;
   }
   
   function setFeeCollector(address _collector) external onlyOwner {
       feeCollector = _collector;
   }
   ```

### Phase 3: 高级功能（可选）
**预期时间**: 3-4 小时

1. **支持的链验证**:
   ```solidity
   function addSupportedDomain(uint32 domain) external onlyOwner {
       supportedDomains[domain] = true;
   }
   
   modifier onlySupportedDomain(uint32 domain) {
       require(supportedDomains[domain], "Domain not supported");
       _;
   }
   ```

2. **批量桥接** (Gas 优化):
   ```solidity
   function batchBridge(
       BridgeParams[] calldata params
   ) external payable nonReentrant {
       // 支持一次交易桥接到多个目标链
   }
   ```

3. **目标链自动接收** (需要 relayer 支持):
   - 在 wrapper 中添加 `receiveMessage()` 辅助函数
   - 与 Circle API 集成获取 attestation
   - 需要后端服务监听事件并自动完成目标链交易

---

## 测试计划

### 单元测试
```bash
forge test --match-contract CCTPBridgeWrapperTest -vvv
```

测试用例：
1. ✅ 正常桥接流程
2. ✅ 余额不足时 revert
3. ✅ 未 approve 时 revert
4. ✅ Relayer 费用正确扣除
5. ✅ 不支持的 domain revert
6. ✅ 升级功能正常工作

### 集成测试（Fork Testing）
```bash
forge test --fork-url $MAINNET_RPC --match-contract CCTPIntegrationTest
```

测试场景：
1. Ethereum → Arbitrum
2. Polygon → Base
3. 验证 messageHash 可在 Circle Explorer 查到

### Mainnet 部署前检查
- [ ] Audit（可选，用 Slither 静态分析）
- [ ] Gas 优化（`forge snapshot`）
- [ ] 多签部署（Gnosis Safe）
- [ ] 文档完善（README + 接口说明）

---

## 部署计划

### 支持的链（Phase 1）
| Chain     | Chain ID | CCTP Domain | USDC Address                                 | TokenMessenger Address                       |
|-----------|----------|-------------|----------------------------------------------|----------------------------------------------|
| Ethereum  | 1        | 0           | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` | `0xBd3fa81B58Ba92a82136038B25aDec7066af3155` |
| Arbitrum  | 42161    | 3           | `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` | `0x19330d10D9Cc8751218eaf51E8885D058642E08A` |
| Base      | 8453     | 6           | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | `0x1682Ae6375C4E4A97e4B583BC394c861A46D8962` |
| Polygon   | 137      | 7           | `0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359` | `0x9daF8c91AEFAE50b9c0E69629D3F6Ca40cA3B3FE` |

### 部署流程
```bash
# 1. 部署实现合约
forge script script/DeployCCTP.s.sol --rpc-url $RPC_ETH --broadcast

# 2. 部署代理合约
forge script script/DeployCCTP.s.sol --rpc-url $RPC_ETH --broadcast --sig "deployProxy()"

# 3. 验证合约
forge verify-contract $IMPL_ADDRESS CCTPBridgeWrapper \
  --chain mainnet --etherscan-api-key $API_KEY

# 4. 初始化
cast send $PROXY_ADDRESS \
  "initialize(address,address,address)" \
  $TOKEN_MESSENGER $USDC $OWNER \
  --private-key $PRIVATE_KEY
```

---

## 文档 & 示例

### README.md 示例
```markdown
# Circle CCTP Bridge Wrapper

One-click USDC cross-chain bridge powered by Circle's CCTP.

## Quick Start

### 1. Approve USDC
\`\`\`bash
cast send $USDC "approve(address,uint256)" $WRAPPER 1000000000
\`\`\`

### 2. Bridge USDC (e.g., Ethereum → Arbitrum)
\`\`\`bash
cast send $WRAPPER \
  "bridge(uint256,uint32,address)" \
  1000000 3 $RECIPIENT_ADDRESS
\`\`\`

### 3. Track transaction
Check status on [Circle Explorer](https://iris-api.circle.com/attestations/$MESSAGE_HASH)
\`\`\`

---

## 风险 & 注意事项

### 安全风险
1. **Max Approval 风险**: 
   - Wrapper 初始化时对 TokenMessenger max approve
   - 如果 TokenMessenger 有漏洞，可能导致 wrapper 中的 USDC 被盗
   - 缓解：Circle 是知名协议，TokenMessenger 已被审计

2. **升级风险**:
   - UUPS 模式下，owner 有权升级实现合约
   - 建议使用多签（Gnosis Safe）控制 owner

3. **Relayer 信任问题**:
   - 如果用户选择 relayer 自动完成目标链交易，需要信任 relayer 不会作恶
   - 缓解：提供无 relayer 模式，让用户自己完成目标链交易

### 功能限制
1. **不支持原生 ETH**: 
   - CCTP 只支持 USDC，无法像 LayerZero 一样传递任意 token

2. **Attestation 延迟**:
   - Circle 的 attestation 通常需要 10-20 分钟
   - 比 LayerZero 的几分钟慢

3. **链支持有限**:
   - 目前 CCTP 只支持少数主流链（Ethereum, Arbitrum, Base, Polygon 等）
   - LayerZero 支持更多链

---

## 下一步

### 短期（1-2 周）
- [ ] 完成 Phase 1 MVP 开发
- [ ] 在测试网（Sepolia, Arbitrum Sepolia）部署测试
- [ ] 编写完整的单元测试和集成测试
- [ ] 部署到主网（先部署 1-2 条链试运行）

### 中期（1 个月）
- [ ] 添加 Relayer 费用功能（Phase 2）
- [ ] 开发前端 UI（Next.js + wagmi）
- [ ] 集成 Circle API 获取 attestation 状态
- [ ] 编写详细的用户文档

### 长期（2-3 个月）
- [ ] 支持更多链（Optimism, Avalanche 等）
- [ ] 开发 Relayer 服务（自动完成目标链交易）
- [ ] 审计（如果 TVL 较大）
- [ ] 社区推广

---

## 参考资料

- [Circle CCTP Docs](https://developers.circle.com/stablecoins/docs/cctp-getting-started)
- [CCTP Contract Addresses](https://developers.circle.com/stablecoins/docs/cctp-technical-reference#mainnet)
- [LayerZero OFT Standard](https://docs.layerzero.network/contracts/oft)
- [OpenZeppelin UUPS Proxy](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable)

---

**作者**: Tangyuan ⚪  
**日期**: 2026-02-20  
**版本**: v1.0
