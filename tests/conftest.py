from asyncio import sleep
import time
import pytest
from brownie import *

@pytest.fixture
def rando(accounts):
  return accounts[6]

@pytest.fixture
def dev(accounts):
  return accounts[1]

@pytest.fixture
def user(accounts):
  return accounts[2]

@pytest.fixture
def gov(accounts):
  return accounts[0]

@pytest.fixture
def cappedGuestListFactory(gov, CappedGuestListFactory):
    cappedGuestListFactory = gov.deploy(CappedGuestListFactory)
    yield cappedGuestListFactory


@pytest.fixture
def onChainPriceFetcher(gov, OnChainPriceFetcher):
    onChainPriceFetcher = gov.deploy(OnChainPriceFetcher,
      # _CURVE_ROUTER: 
      "0x0000000000000000000000000000000000000000",
      # _SOLIDLY_ROUTER: 
      "0x0000000000000000000000000000000000000000", 
      # _QUOTE_USD_TOKEN (USDC): 
      "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
    )

    # [SushiSwap] cvxCRV => USDC    
    onChainPriceFetcher.updatePairRouter("0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F", 
    [
      "0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7",
    "0xD533a949740bb3306d119CC777fa900bA034cd52", 
    "0x6B175474E89094C44Da98b954EedeAC495271d0F", "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
    ])

    # [SushiSwap] WBTC => USDC    
    onChainPriceFetcher.updatePairRouter("0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F", ["0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599","0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"])

    yield onChainPriceFetcher

@pytest.fixture
def priceCalculator(gov, PriceCalculator, onChainPriceFetcher, offChainPriceOracle):
    priceCalculator = gov.deploy(PriceCalculator)
    priceCalculator.initialize({"from": gov})

    priceCalculator.addFeeds(
      ["0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7", "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599", "0x3472A5A71965499acd81997a54BBA8D852C6E53d"], 
      [
        [onChainPriceFetcher.address, "0x0000000000000000000000000000000000000000"],
        [onChainPriceFetcher.address, "0x0000000000000000000000000000000000000000"],
        ["0x0000000000000000000000000000000000000000", offChainPriceOracle.address]
      ]
    )
    yield priceCalculator

@pytest.fixture
def lPPriceCalculator(gov, priceCalculator, LPPriceCalculator):
    lPPriceCalculator = gov.deploy(LPPriceCalculator, priceCalculator)

    priceCalculator.addFeeds(
      ["0xcD7989894bc033581532D2cd88Da5db0A4b12859"],
      [
        [lPPriceCalculator.address, "0x0000000000000000000000000000000000000000"]
      ]
    )

    yield lPPriceCalculator

@pytest.fixture
def offChainPriceOracle(gov, OffChainPriceOracle):
    offChainPriceOracle = gov.deploy(OffChainPriceOracle)
    # Badger in USD (1e18) = 7e18
    offChainPriceOracle.update(
      ["0x3472A5A71965499acd81997a54BBA8D852C6E53d"],
      [7e18],
      {"from": gov},
    )
    yield offChainPriceOracle

@pytest.fixture
def guestlist(gov, vault_one, cappedGuestListFactory, priceCalculator, CappedGuestList):
    guestlist_proxy = cappedGuestListFactory.createCappedGuestList(
        1,
        gov,
        vault_one,
        priceCalculator,
        1e20,
        1e56,
        {"from": gov},
    )

    yield CappedGuestList.at(guestlist_proxy.return_value)

@pytest.fixture
def guestlist_two(gov, vault_two, cappedGuestListFactory, priceCalculator,CappedGuestList):
    guestlist_proxy = cappedGuestListFactory.createCappedGuestList(
        1,
        gov,
        vault_two,
        priceCalculator,
        1e20,
        1e56,
        {"from": gov},
    )

    yield CappedGuestList.at(guestlist_proxy.return_value)


@pytest.fixture
def vault_one():
  # token: Convex CRV (cvxCRV) = 0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7
  yield Contract.from_explorer("0x2B5455aac8d64C14786c3a29858E43b5945819C0", "0x0B7Cb84bc7ad4aF3E1C5312987B6E9A4612068AD")

@pytest.fixture
def want_one():
  sleep(1);
  yield Contract.from_explorer("0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7")

@pytest.fixture
def want_one_rich():
  yield "0xE4360E6e45F5b122586BCA3b9d7b222EA69C5568"

@pytest.fixture
def vault_one_gov():
  yield "0xB65cef03b9B89f99517643226d76e286ee999e77"


@pytest.fixture
def vault_two():
  # token: Uniswap WBTC/BADGER LP (UNI-V2) = 0xcD7989894bc033581532D2cd88Da5db0A4b12859
  yield Contract.from_explorer("0x235c9e24D3FB2FAFd58a2E49D454Fdcd2DBf7FF1", "0xE4Ae305b08434bF3D74e0086592627F913a258A9")

@pytest.fixture
def want_two():
  yield Contract.from_explorer("0xcD7989894bc033581532D2cd88Da5db0A4b12859")


@pytest.fixture
def want_two_rich():
  yield "0x0c79406977314847a9545b11783635432d7fe019"

@pytest.fixture
def vault_two_gov():
  yield "0xB65cef03b9B89f99517643226d76e286ee999e77"

## Forces reset before each test
@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass