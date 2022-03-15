// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import '../libraries/FixedPoint.sol';
import "../interfaces/IUniv2LikePair.sol";

interface IMarketOracle {
    function getData(address tokenAddress) external view returns (uint256);
}

// library with helper methods for oracles that are concerned with computing average prices
library UniswapV2OracleLibrary {
    using FixedPoint for uint112;

    // helper function that returns the current block timestamp within the range of uint32, i.e. [0, 2**32 - 1]
    function currentBlockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp % 2 ** 32);
    }

    // produces the cumulative price using counterfactuals to save gas and avoid a call to sync.
    function currentCumulativePrices(
        address pair
    ) internal view returns (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) {
        blockTimestamp = currentBlockTimestamp();
        price0Cumulative = IUniv2LikePair(pair).price0CumulativeLast();
        price1Cumulative = IUniv2LikePair(pair).price1CumulativeLast();

        // if time has elapsed since the last update on the pair, mock the accumulated price values
        (uint112 reserve0, uint112 reserve1, uint32 timestampLast) = IUniv2LikePair(pair).getReserves();
        if (timestampLast != blockTimestamp) {
            // subtraction overflow is desired
            uint32 timeElapsed = blockTimestamp - timestampLast;
            // addition overflow is desired
            // counterfactual
            price0Cumulative += uint(FixedPoint.fraction(reserve1, reserve0)._x) * timeElapsed;
            // counterfactual
            price1Cumulative += uint(FixedPoint.fraction(reserve0, reserve1)._x) * timeElapsed;
        }
    }
}

contract MarketOracle is IMarketOracle, AccessControl {
    using FixedPoint for FixedPoint.uq112x112;
    using FixedPoint for FixedPoint.uq144x112;

    struct TokenPrice {
        uint    price0CumulativeLast;
        uint    price1CumulativeLast;
        uint    tokenValueInUSDAverage;
        uint32  timestampLast;
    }

    bytes32 public constant CONFIGURATOR_ROLE = keccak256("CONFIGURATOR_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    // USD  (USDC / MIM / 3CRV)
    address public immutable QUOTE_USD_TOKEN;
    uint256 public immutable QUOTE_USD_DECIMAL;

    mapping(address => TokenPrice) public priceList;
    mapping(address => IUniv2LikePair) public tokenLP;

    address public controller;

    constructor(address _QUOTE_USD_TOKEN) {
        QUOTE_USD_TOKEN = _QUOTE_USD_TOKEN;
        QUOTE_USD_DECIMAL = IERC20Metadata(_QUOTE_USD_TOKEN).decimals();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(CONFIGURATOR_ROLE, msg.sender);
        _setupRole(KEEPER_ROLE, msg.sender);
    }

    function _setTokenLP(address _token, address _tokenLP) private {
        tokenLP[_token] = IUniv2LikePair(_tokenLP);
        require(tokenLP[_token].token0() == QUOTE_USD_TOKEN || tokenLP[_token].token1() == QUOTE_USD_TOKEN, "no_usd_token");

        uint price0CumulativeLast = tokenLP[_token].price0CumulativeLast();
        uint price1CumulativeLast = tokenLP[_token].price1CumulativeLast();

        (,,uint32 timestampLast) = tokenLP[_token].getReserves();

        delete priceList[_token]; // reset
        TokenPrice storage tokenPriceInfo = priceList[_token];

        tokenPriceInfo.timestampLast = timestampLast;
        tokenPriceInfo.price0CumulativeLast = price0CumulativeLast;
        tokenPriceInfo.price1CumulativeLast = price1CumulativeLast;
        tokenPriceInfo.tokenValueInUSDAverage = 0;

        _update(_token);
    }

    function setTokenLP(address[] memory tokenLPPairs) external onlyRole(CONFIGURATOR_ROLE) {
        require(tokenLPPairs.length % 2 == 0);
        uint length = tokenLPPairs.length;
        for (uint i = 0; i < length; i = i + 2) {
            _setTokenLP(tokenLPPairs[i], tokenLPPairs[i + 1]);
        }
    }

    function getTokenPrice(address tokenAddress) public view returns (uint256, uint256, uint32, uint256) {
        (uint price0Cumulative, uint price1Cumulative, uint32 _blockTimestamp) = UniswapV2OracleLibrary.currentCumulativePrices(address(tokenLP[tokenAddress]));
        if (_blockTimestamp == priceList[tokenAddress].timestampLast) {
            return (
                priceList[tokenAddress].price0CumulativeLast,
                priceList[tokenAddress].price1CumulativeLast,
                priceList[tokenAddress].timestampLast,
                priceList[tokenAddress].tokenValueInUSDAverage
            );
        }

        uint32 timeElapsed = (_blockTimestamp - priceList[tokenAddress].timestampLast);

        FixedPoint.uq112x112 memory tokenValueInUSDAverage =
            tokenLP[tokenAddress].token1() == QUOTE_USD_TOKEN
            ? FixedPoint.uq112x112(uint224(1e18 * (price0Cumulative - priceList[tokenAddress].price0CumulativeLast) / timeElapsed))
            : FixedPoint.uq112x112(uint224(1e18 * (price1Cumulative - priceList[tokenAddress].price1CumulativeLast) / timeElapsed));

        return (price0Cumulative, price1Cumulative, _blockTimestamp, tokenValueInUSDAverage.mul(1).decode144());
    }

    function _update(address tokenAddress) private {
        (uint price0CumulativeLast, uint price1CumulativeLast, uint32 timestampLast, uint256 tokenValueInUSDAverage) = getTokenPrice(tokenAddress);

        TokenPrice storage tokenPriceInfo = priceList[tokenAddress];

        tokenPriceInfo.timestampLast = timestampLast;
        tokenPriceInfo.price0CumulativeLast = price0CumulativeLast;
        tokenPriceInfo.price1CumulativeLast = price1CumulativeLast;
        tokenPriceInfo.tokenValueInUSDAverage = tokenValueInUSDAverage;
    }

    function scalePriceTo1e18(uint256 rawPrice) internal view returns(uint256) {
        if (QUOTE_USD_DECIMAL <= 18) {
        return rawPrice * (10**(18 - QUOTE_USD_DECIMAL));
        } else {
        return rawPrice / (10**(QUOTE_USD_DECIMAL - 18));
        }
    }

    // Update "last" state variables to current values
    function update(address[] memory tokenAddress) external onlyRole(KEEPER_ROLE) {
        uint length = tokenAddress.length;
        for (uint i = 0; i < length; ++i) {
            _update(tokenAddress[i]);
        }
    }

    // Return the average usd price (1e18) since last update
    function getData(address tokenAddress) external override view returns (uint256) {
        (,,, uint tokenValueInUSDAverage) = getTokenPrice(tokenAddress);
        return scalePriceTo1e18(tokenValueInUSDAverage);
    }

}