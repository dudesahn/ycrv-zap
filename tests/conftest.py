import pytest, requests
from brownie import ZERO_ADDRESS, config, Contract, ZapYCRV, web3, chain

# This causes test not to re-run fixtures on each run
@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass

# @pytest.fixture(scope="module", autouse=True)
# def tenderly_fork(web3, chain):
#     fork_base_url = "https://simulate.yearn.network/fork"
#     payload = {"network_id": str(chain.id)}
#     resp = requests.post(fork_base_url, headers={}, json=payload)
#     fork_id = resp.json()["simulation_fork"]["id"]
#     fork_rpc_url = f"https://rpc.tenderly.co/fork/{fork_id}"
#     print(fork_rpc_url)
#     tenderly_provider = web3.HTTPProvider(fork_rpc_url, {"timeout": 600})
#     web3.provider = tenderly_provider
#     print(f"https://dashboard.tenderly.co/yearn/yearn-web/fork/{fork_id}")

@pytest.fixture
def gov(accounts):
    yield accounts.at("0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52", force=True)
    #yield accounts.at("0x6AFB7c9a6E8F34a3E0eC6b734942a5589A84F44C", force=True)

@pytest.fixture
def yvboost():
    yield Contract("0x9d409a0A012CFbA9B15F6D4B36Ac57A46966Ab9a")

@pytest.fixture
def yveCrv():
    yield Contract("0xc5bDdf9843308380375a611c18B50Fb9341f502A")

@pytest.fixture
def whale_yvboost(accounts):
    yield accounts.at("0xe896e539e557BC751860a7763C8dD589aF1698Ce", force=True)

@pytest.fixture
def user(accounts, yveCrv, yvboost, crv, whale_yvecrv, whale_crv, whale_yvboost, cvxcrv, whale_cvxcrv):
    yvboost.transfer(accounts[0], 500e18,{'from':whale_yvboost})
    crv.transfer(accounts[0], 500e18,{'from':whale_crv})
    yveCrv.transfer(accounts[0], 1_000e18,{'from':whale_yvecrv})
    cvxcrv.transfer(accounts[0], 1_000e18,{'from':whale_cvxcrv})
    yield accounts[0]

@pytest.fixture
def rewards(accounts):
    yield accounts[1]


@pytest.fixture
def guardian(accounts):
    yield accounts[2]


@pytest.fixture
def management(accounts):
    yield accounts.at("0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7", force=True)


@pytest.fixture
def strategist(accounts):
    yield accounts.at("0x6AFB7c9a6E8F34a3E0eC6b734942a5589A84F44C", force=True)


@pytest.fixture
def keeper(accounts):
    yield accounts.at("0x13dAda6157Fee283723c0254F43FF1FdADe4EEd6", force=True)


@pytest.fixture
def rando(accounts):
    yield accounts[6]


@pytest.fixture
def token():
    token_address = "0xc5bDdf9843308380375a611c18B50Fb9341f502A"  # this should be the address of the ERC-20 used by the strategy/vault
    yield Contract(token_address)


@pytest.fixture
def crv():
    yield Contract("0xD533a949740bb3306d119CC777fa900bA034cd52")

@pytest.fixture
def cvxcrv():
    yield Contract("0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7")

@pytest.fixture
def whale_cvxcrv(accounts):
    yield accounts.at("0x3Fe65692bfCD0e6CF84cB1E7d24108E434A7587e", force=True)

@pytest.fixture
def amount(accounts, token, gov):
    amount = 10_000 * 10 ** token.decimals()
    # In order to get some funds for the token you are about to use,
    # it impersonate an exchange address to use it's funds.
    reserve = accounts.at("0xFCc5c47bE19d06BF83eB04298b026F81069ff65b", force=True)
    token.transfer(accounts[0], amount*2, {"from": reserve})
    token.transfer(gov, amount, {"from": reserve})
    yield amount


@pytest.fixture
def vault(pm, gov, rewards, guardian, management, token):
    yield Contract('0x9d409a0A012CFbA9B15F6D4B36Ac57A46966Ab9a')

@pytest.fixture
def eth_whale(accounts):
    yield accounts.at("0x53d284357ec70cE289D6D64134DfAc8E511c8a3D", force=True)


@pytest.fixture
def trade_factory():
    yield Contract("0x7BAF843e06095f68F4990Ca50161C2C4E4e01ec6")

@pytest.fixture
def ymechs_safe():
    yield Contract("0x2C01B4AD51a67E2d8F02208F54dF9aC4c0B778B6")


@pytest.fixture
def sushi_swapper(trade_factory, ymechs_safe):
    yield Contract("0x55dcee9332848AFcF660CE6a2116D83Dd7a71B60")


@pytest.fixture
def live_strat():
    live_strat = Contract('0x7fe508eE30316e3261079e2C81f4451E0445103b')
    yield live_strat

@pytest.fixture
def ycrv(user):
    ycrv = Contract('0xFCc5c47bE19d06BF83eB04298b026F81069ff65b')
    v = '0x27B5739e22ad9033bcBf192059122d163b60349D'
    ycrv.transfer(user, 10_000e18, {'from': v})
    yield ycrv

@pytest.fixture
def ybs(ycrv, user):
    ybs = Contract('0xE9A115b77A1057C918F997c32663FdcE24FB873f')
    ycrv.approve(ybs, 2 ** 256-1, {'from': user})
    ybs.stake(1_000e18, {'from':user})
    yield ybs

@pytest.fixture
def vault_abi():
    return Contract("0x9d409a0A012CFbA9B15F6D4B36Ac57A46966Ab9a").abi

@pytest.fixture
def st_ycrv(strategist, ycrv, gov, yveCrv,vault_abi, user):
    treasury = '0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde'
    st = Contract('0x27B5739e22ad9033bcBf192059122d163b60349D')
    st.transfer(user, 10_000e18, {'from':treasury})
    yield st

@pytest.fixture
def pool(strategist, gov, ycrv, yveCrv, vault_abi, crv, user):
    pool = Contract('0x99f5aCc8EC2Da2BC0771c32814EFF52b712de1E5')
    yveCrv.approve(ycrv,2**256-1, {'from':user})
    ycrv.approve(pool, 2**256-1, {'from':user})
    crv.approve(pool, 2**256-1, {'from':user})
    yield pool

@pytest.fixture
def lp_ycrv(gov, pool, ycrv, user, vault_abi):
    treasury = '0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde'
    lp = Contract('0x6E9455D109202b426169F0d8f01A3332DAE160f3')
    lp.transfer(user, 10_000, {'from': treasury})
    yield lp

@pytest.fixture
def zap(ycrv, strategist, st_ycrv, lp_ycrv, pool):
    z = strategist.deploy(ZapYCRV)
    yield z

@pytest.fixture
def strategy(strategist, live_strat, 
    keeper, vault, Strategy, gov, token, crv3, usdc,
    trade_factory, ymechs_safe
    ):

    live_strat.setDoHealthCheck(False, {"from": gov})

    new_strategy = strategist.deploy(Strategy, vault)
    tx = vault.migrateStrategy(live_strat, new_strategy, {"from":gov})

    new_strategy.setKeeper(keeper, {"from":gov})

    trade_factory.grantRole(trade_factory.STRATEGY(), new_strategy.address, {"from": ymechs_safe, "gas_price": "0 gwei"})
    new_strategy.setTradeFactory(trade_factory.address, {"from": gov})

    yield new_strategy


@pytest.fixture
def crv3():
    yield Contract("0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490")


@pytest.fixture
def usdc():
    yield Contract("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48")


@pytest.fixture
def weth():
    yield Contract("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2")


@pytest.fixture
def old_proxy(strategy, gov):
    p = Contract("0x9a165622a744C20E3B2CB443AeD98110a33a231b")
    yield p



@pytest.fixture
def voter():
    yield Contract("0xF147b8125d2ef93FB6965Db97D6746952a133934")

@pytest.fixture
def new_proxy(strategy, yveCrv, strategist, gov, voter):
    p = strategist.deploy(StrategyProxy)
    # Set up new proxy
    p.setGovernance(gov)
    p.setFeeRecipient(strategy, {"from": gov})
    voter.setStrategy(p, {"from": gov})
    strategy.setProxy(p, {"from": gov})
    yveCrv.setProxy(p, {"from": gov})
    yveCrv.setFeeDistribution(ZERO_ADDRESS, {"from": gov})
    yield p

@pytest.fixture
def yveCrv(token):
    yield token


@pytest.fixture
def whale_eth(accounts):
    yield accounts.at("0x73BCEb1Cd57C711feaC4224D062b0F6ff338501e", force=True)

@pytest.fixture
def whale_yvecrv(accounts):
    yield accounts.at("0x10B47177E92Ef9D5C6059055d92DdF6290848991", force=True)

@pytest.fixture
def whale_3crv(accounts):
    yield accounts.at("0x43b4FdFD4Ff969587185cDB6f0BD875c5Fc83f8c", force=True)

@pytest.fixture
def whale_crv(accounts):
    yield accounts.at("0xe3997288987E6297Ad550A69B31439504F513267", force=True)

@pytest.fixture
def sushiswap_crv(accounts):
    yield accounts.at("0x5c00977a2002a3C9925dFDfb6815765F578a804f", force=True)


@pytest.fixture
def sushiswap(Contract):
    yield Contract("0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F")

@pytest.fixture
def not_banteg(accounts):
    yield accounts.at("0x0035Fc5208eF989c28d47e552E92b0C507D2B318", force=True)

@pytest.fixture
def klim(accounts):
    yield accounts.at("0x279a7DBFaE376427FFac52fcb0883147D42165FF", force=True) # airdropper

@pytest.fixture
def weth_amount(accounts, weth, gov):
    amount = 1e21
    # In order to get some funds for the token you are about to use,
    # it impersonate an exchange address to use it's funds.
    reserve = accounts.at("0x2F0b23f53734252Bda2277357e97e1517d6B042A", force=True)
    weth.transfer(gov, amount, {"from": reserve})
    yield amount

@pytest.fixture(scope="session")
def RELATIVE_APPROX():
    yield 1e-5

@pytest.fixture(scope="module")
def multicall_swapper(interface):
    yield interface.MultiCallOptimizedSwapper(
        "0xB2F65F254Ab636C96fb785cc9B4485cbeD39CDAA"
    )

