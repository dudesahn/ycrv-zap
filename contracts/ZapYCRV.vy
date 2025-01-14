# @version 0.3.9
"""
@title YCRV Zap v4
@license GNU AGPLv3
@author Yearn Finance
@notice Zap into yCRV ecosystem positions in a single transaction
@dev To use safely, supply a reasonable min_out value during your zap.
"""

from vyper.interfaces import ERC20
from vyper.interfaces import ERC20Detailed

interface Vault:
    def deposit(amount: uint256, recipient: address = msg.sender) -> uint256: nonpayable
    def withdraw(shares: uint256) -> uint256: nonpayable
    def pricePerShare() -> uint256: view

interface IYBS:
    def stakeFor(account: address, amount: uint256) -> uint256: nonpayable
    def unstakeFor(account: address, amount: uint256, receiver: address) -> uint256: nonpayable
    def balanceOf(account: address) -> uint256: nonpayable

interface IYCRV:
    def burn_to_mint(amount: uint256, recipient: address = msg.sender) -> uint256: nonpayable
    def mint(amount: uint256, recipient: address = msg.sender) -> uint256: nonpayable

interface Curve:
    def get_virtual_price() -> uint256: view
    def get_dy(i: int128, j: int128, dx: uint256) -> uint256: view
    def exchange(i: int128, j: int128, _dx: uint256, _min_dy: uint256) -> uint256: nonpayable
    def add_liquidity(amounts: uint256[2], min_mint_amount: uint256) -> uint256: nonpayable
    def remove_liquidity_one_coin(_token_amount: uint256, i: int128, min_amount: uint256) -> uint256: nonpayable
    def remove_liquidity(_burn_amount: uint256, _min_amounts: uint256[2]) -> uint256[2]: nonpayable
    def calc_token_amount(amounts: uint256[2], deposit: bool) -> uint256: view
    def calc_withdraw_one_coin(_burn_amount: uint256, i: int128, _previous: bool = False) -> uint256: view
    def totalSupply() -> uint256: view
    def balances(index: uint256) -> uint256: view

event UpdateSweepRecipient:
    sweep_recipient: indexed(address)

event UpdateMintBuffer:
    mint_buffer: uint256

YVECRV: constant(address) =     0xc5bDdf9843308380375a611c18B50Fb9341f502A # YVECRV
CRV: constant(address) =        0xD533a949740bb3306d119CC777fa900bA034cd52 # CRV
YVBOOST: constant(address) =    0x9d409a0A012CFbA9B15F6D4B36Ac57A46966Ab9a # YVBOOST
YCRV: constant(address) =       0xFCc5c47bE19d06BF83eB04298b026F81069ff65b # YCRV
STYCRV: constant(address) =     0x27B5739e22ad9033bcBf192059122d163b60349D # ST-YCRV
LPYCRV_V1: constant(address) =  0xc97232527B62eFb0D8ed38CF3EA103A6CcA4037e # LP-YCRV Deprecated
LPYCRV_V2: constant(address) =  0x6E9455D109202b426169F0d8f01A3332DAE160f3 # LP-YCRV
POOL_V1: constant(address) =    0x453D92C7d4263201C69aACfaf589Ed14202d83a4 # OLD POOL
POOL_V2: constant(address) =    0x99f5aCc8EC2Da2BC0771c32814EFF52b712de1E5 # NEW POOL
CVXCRV: constant(address) =     0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7 # CVXCRV
CVXCRVPOOL: constant(address) = 0x9D0464996170c6B9e75eED71c68B99dDEDf279e8 # CVXCRVPOOL
YBS: constant(address) =        0xE9A115b77A1057C918F997c32663FdcE24FB873f # YBS
LEGACY_TOKENS: public(immutable(address[2]))
OUTPUT_TOKENS: public(immutable(address[4]))

name: public(String[32])
sweep_recipient: public(address)
mint_buffer: public(uint256)

@external
def __init__():
    self.name = "YCRV Zap v3"
    self.sweep_recipient = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52
    self.mint_buffer = 15

    assert ERC20(YVECRV).approve(YCRV, max_value(uint256))
    assert ERC20(YCRV).approve(STYCRV, max_value(uint256))
    assert ERC20(YCRV).approve(POOL_V2, max_value(uint256))
    assert ERC20(POOL_V2).approve(LPYCRV_V2, max_value(uint256))
    assert ERC20(CRV).approve(POOL_V2, max_value(uint256))
    assert ERC20(CRV).approve(YCRV, max_value(uint256))
    assert ERC20(CVXCRV).approve(CVXCRVPOOL, max_value(uint256))

    assert ERC20(YCRV).approve(YBS, max_value(uint256))

    LEGACY_TOKENS = [YVECRV, YVBOOST]
    OUTPUT_TOKENS = [YCRV, STYCRV, LPYCRV_V2, YBS]

@external
def zap(_input_token: address, _output_token: address, _amount_in: uint256 = max_value(uint256), _min_out: uint256 = 0, _recipient: address = msg.sender) -> uint256:
    """
    @notice 
        This function allows users to zap from any legacy tokens, CRV, or any yCRV tokens as input 
        into any yCRV token as output.
    @dev 
        When zapping between tokens that might incur slippage, it is recommended to supply a _min_out value > 0.
        You can estimate the expected output amount by making an off-chain call to this contract's 
        "calc_expected_out" helper.
        Discount the result by some extra % to allow buffer, and set as _min_out.
    @param _input_token Can be CRV, yveCRV, yvBOOST, cvxCRV or any yCRV token address that user wishes to migrate from
    @param _output_token The yCRV token address that user wishes to migrate to
    @param _amount_in Amount of input token to migrate, defaults to full balance
    @param _min_out The minimum amount of output token to receive
    @param _recipient The address where the output token should be sent
    @return Amount of output token transferred to the _recipient
    """
    assert _amount_in > 0
    assert _input_token != _output_token # dev: input and output token are same
    assert _output_token in OUTPUT_TOKENS  # dev: invalid output token address

    amount: uint256 = _amount_in
    if amount == max_value(uint256):
        amount = ERC20(_input_token).balanceOf(msg.sender)

    if _input_token in LEGACY_TOKENS:
        return self._zap_from_legacy(_input_token, _output_token, amount, _min_out, _recipient)
    elif _input_token == CRV or _input_token == CVXCRV:
        assert ERC20(_input_token).transferFrom(msg.sender, self, amount)
        if _input_token == CVXCRV:
            amount = Curve(CVXCRVPOOL).exchange(1, 0, amount, 0)
        amount = self._convert_crv(amount)
    elif _input_token in [LPYCRV_V1, POOL_V1]:
        # If this input token path is chosen, we assume it is a migration. 
        # This allows us to hardcode a single route, 
        # no need for many permutations to all possible outputs.
        assert _output_token == LPYCRV_V2
        assert ERC20(_input_token).transferFrom(msg.sender, self, amount)
        if _input_token == LPYCRV_V1:
            amount = Vault(LPYCRV_V1).withdraw(amount)
        amounts: uint256[2] = Curve(POOL_V1).remove_liquidity(amount, [0,0])
        amount = Curve(POOL_V2).add_liquidity(amounts, 0)
        amount = Vault(LPYCRV_V2).deposit(amount, _recipient)
        assert amount >= _min_out
        return amount
    else:
        assert _input_token in OUTPUT_TOKENS or _input_token == POOL_V2 # dev: invalid input token address
        if _input_token != YBS:
            assert ERC20(_input_token).transferFrom(msg.sender, self, amount)

    if _input_token == STYCRV:
        amount = Vault(STYCRV).withdraw(amount)
    elif _input_token == YBS:
        amount = IYBS(YBS).unstakeFor(msg.sender, amount, self)
    elif _input_token in [LPYCRV_V2, POOL_V2]:
        if _input_token == LPYCRV_V2:
            amount = Vault(LPYCRV_V2).withdraw(amount)
        amount = Curve(POOL_V2).remove_liquidity_one_coin(amount, 1, 0)

    if _output_token == YCRV:
        assert amount >= _min_out # dev: min out
        ERC20(_output_token).transfer(_recipient, amount)
        return amount
    return self._convert_to_output(_output_token, amount, _min_out, _recipient)

@internal
def _zap_from_legacy(_input_token: address, _output_token: address, _amount: uint256, _min_out: uint256, _recipient: address) -> uint256:
    # @dev This function handles any inputs that are legacy tokens (yveCRV, yvBOOST)
    amount: uint256 = _amount
    assert ERC20(_input_token).transferFrom(msg.sender, self, amount)
    if _input_token == YVBOOST:
        amount = Vault(YVBOOST).withdraw(amount)

    # Mint YCRV
    if _output_token == YCRV:
        IYCRV(YCRV).burn_to_mint(amount, _recipient)
        assert amount >= _min_out # dev: min out
        return amount
    IYCRV(YCRV).burn_to_mint(amount)
    return self._convert_to_output(_output_token, amount, _min_out, _recipient)
    
@internal
def _convert_crv(amount: uint256) -> uint256:
    output_amount: uint256 = Curve(POOL_V2).get_dy(0, 1, amount)
    buffered_amount: uint256 = amount + (amount * self.mint_buffer / 10_000)
    if output_amount > buffered_amount:
        return Curve(POOL_V2).exchange(0, 1, amount, 0)
    else:
        return IYCRV(YCRV).mint(amount)

@internal
def _lp(_amounts: uint256[2]) -> uint256:
    return Curve(POOL_V2).add_liquidity(_amounts, 0)

@internal
def _convert_to_output(_output_token: address, amount: uint256, _min_out: uint256, _recipient: address) -> uint256:
    # dev: output token and amount values have already been validated
    amount_out: uint256 = 0
    if _output_token == STYCRV:
        amount_out = Vault(STYCRV).deposit(amount, _recipient)
        assert amount_out >= _min_out # dev: min out
        return amount_out
    elif _output_token == YBS:
        amount_out = IYBS(YBS).stakeFor(_recipient, amount)
        assert amount_out + 1 >= _min_out # dev: min out
        return amount_out
    assert _output_token == LPYCRV_V2
    amount_out = Vault(LPYCRV_V2).deposit(self._lp([0, amount]), _recipient)
    assert amount_out >= _min_out # dev: min out
    return amount_out

@view
@internal
def _relative_price_from_legacy(_input_token: address, _output_token: address, _amount_in: uint256) -> uint256:
    if _amount_in == 0:
        return 0

    amount: uint256 = _amount_in
    if _input_token == YVBOOST:
        amount = Vault(YVBOOST).pricePerShare() * amount / 10 ** 18
    
    if _output_token in [YCRV, YBS]:
        return amount
    elif _output_token == STYCRV:
        return amount * 10 ** 18 / Vault(STYCRV).pricePerShare()
    assert _output_token == LPYCRV_V2
    lp_amount: uint256 = amount * 10 ** 18 / Curve(POOL_V2).get_virtual_price()
    return lp_amount * 10 ** 18 / Vault(LPYCRV_V2).pricePerShare()

@view
@external
def relative_price(_input_token: address, _output_token: address, _amount_in: uint256) -> uint256:
    """
    @notice 
        This returns a rough amount of output assuming there's a balanced liquidity pool.
        The return value should not be relied upon for an accurate estimate for actual output amount.
    @dev 
        This value should only be used to compare against "calc_expected_out_from_legacy" to project price impact.
    @param _input_token The token to migrate from
    @param _output_token The yCRV token to migrate to
    @param _amount_in Amount of input token to migrate, defaults to full balance
    @return Amount of output token transferred to the _recipient
    """
    assert _output_token in OUTPUT_TOKENS  # dev: invalid output token address
    if _input_token in LEGACY_TOKENS:
        return self._relative_price_from_legacy(_input_token, _output_token, _amount_in)
    assert (
        _input_token in [CRV , CVXCRV , LPYCRV_V1 , POOL_V1, POOL_V2]
        or _input_token in OUTPUT_TOKENS
    ) # dev: invalid input token address

    if _amount_in == 0:
        return 0
    amount: uint256 = _amount_in
    if _input_token == _output_token:
        return _amount_in
    elif _input_token == STYCRV:
        amount = Vault(STYCRV).pricePerShare() * amount / 10 ** 18
    elif _input_token in [LPYCRV_V2, POOL_V2]:
        if _input_token == LPYCRV_V2:
            amount = Vault(LPYCRV_V2).pricePerShare() * amount / 10 ** 18
        amount = Curve(POOL_V2).get_virtual_price() * amount / 10 ** 18
    elif _input_token in [LPYCRV_V1, POOL_V1]:
        assert _output_token == LPYCRV_V2
        if _input_token == LPYCRV_V1:
            amount = Vault(LPYCRV_V1).pricePerShare() * amount / 10 ** 18
        amount = Curve(POOL_V1).get_virtual_price() * amount / 10 ** 18

    if _output_token in [YCRV, YBS]:
        return amount
    elif _output_token == STYCRV:
        return amount * 10 ** 18 / Vault(STYCRV).pricePerShare()

    assert _output_token == LPYCRV_V2
    lp_amount: uint256 = amount * 10 ** 18 / Curve(POOL_V2).get_virtual_price()
    return lp_amount * 10 ** 18 / Vault(LPYCRV_V2).pricePerShare()

@view
@internal
def _calc_expected_out_from_legacy(_input_token: address, _output_token: address, _amount_in: uint256) -> uint256:
    if _amount_in == 0:
        return 0
    amount: uint256 = _amount_in
    if _input_token == YVBOOST:
        amount = Vault(YVBOOST).pricePerShare() * amount / 10 ** 18
    
    if _output_token in [YCRV, YBS]:
        return amount
    elif _output_token == STYCRV:
        return amount * 10 ** 18 / Vault(STYCRV).pricePerShare()
    assert _output_token == LPYCRV_V2
    lp_amount: uint256 = Curve(POOL_V2).calc_token_amount([0, amount], True)
    return lp_amount * 10 ** 18 / Vault(LPYCRV_V2).pricePerShare()

@view
@external
def calc_expected_out(_input_token: address, _output_token: address, _amount_in: uint256) -> uint256:
    """
    @notice 
        This returns the expected amount of tokens output after conversion.
    @dev
        This calculation accounts for slippage, but not fees.
        Needed to prevent front-running, do not rely on it for precise calculations!
    @param _input_token A valid input token address to migrate from
    @param _output_token The yCRV token address to migrate to
    @param _amount_in Amount of input token to migrate, defaults to full balance
    @return Amount of output token transferred to the _recipient
    """
    assert _output_token in OUTPUT_TOKENS  # dev: invalid output token address
    assert _input_token != _output_token
    if _input_token in LEGACY_TOKENS:
        return self._calc_expected_out_from_legacy(_input_token, _output_token, _amount_in)
    amount: uint256 = _amount_in

    if _input_token == CRV or _input_token == CVXCRV:
        if _input_token == CVXCRV:
            amount = Curve(CVXCRVPOOL).get_dy(1, 0, amount)
        output_amount: uint256 = Curve(POOL_V2).get_dy(0, 1, amount)
        buffered_amount: uint256 = amount + (amount * self.mint_buffer / 10_000)
        if output_amount > buffered_amount: # dev: ensure calculation uses buffer
            amount = output_amount
    elif _input_token in [LPYCRV_V1, POOL_V1]:
        assert _output_token == LPYCRV_V2
        if _input_token == LPYCRV_V1:
            amount = Vault(LPYCRV_V1).pricePerShare() * amount / 10 ** 18
        amounts: uint256[2] = self.assets_amounts_from_lp(POOL_V1, amount)
        amount = Curve(POOL_V2).calc_token_amount(amounts, True) # Deposit
        return amount * 10 ** 18 / Vault(LPYCRV_V2).pricePerShare()
    else:
        assert _input_token in OUTPUT_TOKENS or _input_token == POOL_V2   # dev: invalid input token address
    
    if amount == 0:
        return 0

    if _input_token == STYCRV:
        amount = Vault(STYCRV).pricePerShare() * amount / 10 ** 18
    elif _input_token in [LPYCRV_V2, POOL_V2]:
        if _input_token == LPYCRV_V2:
            amount = Vault(LPYCRV_V2).pricePerShare() * amount / 10 ** 18
        amount = Curve(POOL_V2).calc_withdraw_one_coin(amount, 1)

    if _output_token in [YCRV, YBS]:
        return amount
    elif _output_token == STYCRV:
        return amount * 10 ** 18 / Vault(STYCRV).pricePerShare()
    
    assert _output_token == LPYCRV_V2
    lp_amount: uint256 = Curve(POOL_V2).calc_token_amount([0, amount], True)
    return lp_amount * 10 ** 18 / Vault(LPYCRV_V2).pricePerShare()

@view
@internal
def assets_amounts_from_lp(pool: address, _lp_amount: uint256) -> uint256[2]:
    supply: uint256 = Curve(pool).totalSupply()
    ratio: uint256 = _lp_amount * 10 ** 18 / supply
    balance0: uint256 = Curve(pool).balances(0) * ratio / 10 ** 18
    balance1: uint256 = Curve(pool).balances(1) * ratio / 10 ** 18
    return [balance0, balance1]

@external
def sweep(_token: address, _amount: uint256 = max_value(uint256)):
    assert msg.sender == self.sweep_recipient
    value: uint256 = _amount
    if value == max_value(uint256):
        value = ERC20(_token).balanceOf(self)
    assert ERC20(_token).transfer(self.sweep_recipient, value, default_return_value=True)

@external
def set_mint_buffer(_new_buffer: uint256):
    """
    @notice 
        Allow SWEEP_RECIPIENT to express a preference towards minting over swapping 
        to save gas and improve overall locked position
    @param _new_buffer New percentage (expressed in BPS) to nudge zaps towards minting
    """
    assert msg.sender == self.sweep_recipient
    assert _new_buffer < 500 # dev: buffer too high
    self.mint_buffer = _new_buffer
    log UpdateMintBuffer(_new_buffer)

@external
def set_sweep_recipient(_proposed_sweep_recipient: address):
    assert msg.sender == self.sweep_recipient
    self.sweep_recipient = _proposed_sweep_recipient
    log UpdateSweepRecipient(_proposed_sweep_recipient)