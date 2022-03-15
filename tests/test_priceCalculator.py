import brownie
from brownie import *


def test_price_calculator(priceCalculator, lPPriceCalculator, want_two):

    # Wrapped BTC ~38,000.00 usd
    px0 = priceCalculator.tokenPriceInUSD("0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599", 1e8)
    assert px0 > 30000*1e18
    assert px0 < 80000*1e18

    # Badger ~7 usd
    px1 = priceCalculator.tokenPriceInUSD("0x3472A5A71965499acd81997a54BBA8D852C6E53d", 1e18)
    assert px1 > 6*1e18 
    assert px1 < 8*1e18 
    # Uniswap WBTC/BADGER LP (UNI-V2)  ~124,932,252.99usd

    lp_price = lPPriceCalculator.getData(want_two)
    want_two_price = priceCalculator.tokenPriceInUSD(want_two, 1e18)

    assert lp_price > 120000000*1e18
    assert lp_price < 180000000*1e18

    assert want_two_price > 120000000*1e18

