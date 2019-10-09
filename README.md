# pchain-contracts

1. 部署合约，获得合约地址：

ApostleBase.sol

ApostleClockAuction.sol

ApostleSettingIds.sol

Gen0Apostle.sol

ObjectOwnership.sol

InterstellarEncoder.sol

SettingsRegistry.sol

ApostleBaseProxy（OwnedUpgradeabilityProxy）

ApostleClockAuctionProxy（OwnedUpgradeabilityProxy）

Gen0ApostleProxy（OwnedUpgradeabilityProxy）

ObjectOwnershipProxy（OwnedUpgradeabilityProxy）

ObjectOwnershipAuthority.sol(使用ApostleBaseProxy初始化)

ApostleBaseAuthority.sol(使用Gen0ApostleProxy初始化)

ClockAuctionAuthority.sol(使用Gen0ApostleProxy初始化)

2. 设置proxy
1）OwnedUpgradeabilityProxy，调用upgradeTo设置implementation
ApostleBase
ApostleClockAuction
Gen0Apostle
ObjectOwnership
2）调用proxy的initialize_contract方法初始化，初始填写SettingsRegistry，Gen0的第二个参数为2000
ApostleBaseProxy
ApostleClockAuctionProxy
Gen0ApostleProxy
ObjectOwnershipProxy

3. 设置常量
将ApostleSettingIds中的常量设置到SettingsRegistry中，
CONTRACT_OBJECT_OWNERSHIP = ObjectOwnershipProxy
CONTRACT_INTERSTELLAR_ENCODER = InterstellarEncoder
CONTRACT_REVENUE_POOL = 收款资金账户
UINT_AUCTION_CUT = 400 (4%)
UINT_REFERER_CUT = 2000 (20%)
UINT_AUTOBIRTH_FEE = 500000000000000000000
CONTRACT_APOSTLE_BASE = ApostleBaseProxy
CONTRACT_APOSTLE_AUCTION = ApostleClockAuctionProxy
UINT_MIX_TALENT = 5000000000000000000
UINT_APOSTLE_BID_WAITING_TIME = 600

4. 设置authority
ObjectOwnershipProxy 调用 setAuthority 参数为 ObjectOwnershipAuthority
ApostleBaseProxy 调用 setAuthority 参数为 ApostleBaseAuthority
ApostleClockAuctionProxy 调用 setAuthority 参数为 ClockAuctionAuthority

5. Encoder注册
InterstellerEncoder 调用 registerNewObjectClass 参数填写ApostleBaseProxy,2
调用 registerNewTokenContract 参数填写 ObjectOwnershipProxy

6. 设置operator
将Gen0ApostleProxy的operator设置为调用合约者的账户地址
