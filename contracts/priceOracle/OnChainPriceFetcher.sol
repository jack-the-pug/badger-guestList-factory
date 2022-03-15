// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import '../interfaces/IPriceFeed.sol';
import '../interfaces/IBaseV1Router01.sol';
import '../interfaces/IUniv2LikeRouter01.sol';
import '../interfaces/ICurveRouter.sol';

contract OnChainPriceFetcher is IPriceFeed, Ownable {

    struct TokenPairInfo {
        // ROUTER
        address router;
        // swap path
        address[] path;
    }

    address public immutable CURVE_ROUTER;
    address public immutable SOLIDLY_ROUTER;
    // USD  (USDC / MIM / 3CRV)
    address public immutable QUOTE_USD_TOKEN;
    uint256 public immutable QUOTE_USD_DECIMAL;

    /// @notice Info of each TokenPair
    mapping(uint => TokenPairInfo) public pairRouter;

    constructor(address _CURVE_ROUTER, address _SOLIDLY_ROUTER, address _QUOTE_USD_TOKEN) {
        CURVE_ROUTER = _CURVE_ROUTER;
        SOLIDLY_ROUTER = _SOLIDLY_ROUTER;
        QUOTE_USD_TOKEN = _QUOTE_USD_TOKEN;

        QUOTE_USD_DECIMAL = IERC20Metadata(_QUOTE_USD_TOKEN).decimals();
    }

    function getData(address token) external view returns(uint256 priceInUSD) {
        uint256 amount = 10 ** IERC20Metadata(token).decimals();
        // Check Solidly
        uint256 solidlyQuote = getSolidlyQuote(token, amount, QUOTE_USD_TOKEN);
        // Check Curve
        uint256 curveQuote = getCurveQuote(token, amount, QUOTE_USD_TOKEN);

        priceInUSD = Math.max(curveQuote, solidlyQuote);

        try this.getUniV2Quote(token, amount, QUOTE_USD_TOKEN) returns (uint256 uniV2Quote) {
            if (uniV2Quote > 0) {
                priceInUSD = priceInUSD > 0 ? Math.average(priceInUSD, uniV2Quote) : uniV2Quote;
            }
        } catch (bytes memory) {
            // We ignore as it means it's zero
        }
    }

    function getUniV2Quote(address fromToken, uint256 amount, address toToken) public view returns(uint256) {
        (address router, address[] memory path) = getRouterAndPath(fromToken,toToken);

        uint256[] memory amounts = IUniv2LikeRouter01(router).getAmountsOut(amount, path);

        return scalePriceTo1e18(amounts[amounts.length - 1]);
    }

    function getSolidlyQuote(address fromToken, uint256 amount, address toToken) public view returns(uint256) {
        if (SOLIDLY_ROUTER == address(0)) return 0;

        (uint256 solidlyQuote,) = IBaseV1Router01(SOLIDLY_ROUTER).getAmountOut(amount, fromToken, toToken);

        return scalePriceTo1e18(solidlyQuote);
    }

    function getCurveQuote(address fromToken, uint256 amount, address toToken) public view returns(uint256) {
        if (CURVE_ROUTER == address(0)) return 0;

        (, uint256 curveQuote) = ICurveRouter(CURVE_ROUTER).get_best_rate(fromToken, toToken, amount);

        return scalePriceTo1e18(curveQuote);
    }

    function scalePriceTo1e18(uint256 rawPrice) internal view returns(uint256) {
        if (QUOTE_USD_DECIMAL <= 18) {
            return rawPrice * (10**(18 - QUOTE_USD_DECIMAL));
        } else {
            return rawPrice / (10**(QUOTE_USD_DECIMAL - 18));
        }
    }

    // --------------------------------------------------------------
    // ROUTER Manage
    // --------------------------------------------------------------

    function updatePairRouter(address router, address[] calldata path) external onlyOwner {
        uint pairKey = uint(uint160(path[0])) + uint(uint160(path[path.length - 1]));
        TokenPairInfo storage pairInfo = pairRouter[pairKey];

        pairInfo.router = router;
        pairInfo.path = path;
    }
    

    // --------------------------------------------------------------
    // Internal
    // --------------------------------------------------------------

    function getRouterAndPath(address fromToken, address toToken) internal view returns (address router, address[] memory path) {
        uint pairKey = uint(uint160(fromToken)) + uint(uint160(toToken));
        TokenPairInfo storage pairInfo = pairRouter[pairKey];

        require(pairInfo.router != address(0), "router not set");

        router = pairInfo.router;

        path = new address[](pairInfo.path.length);
        if (pairInfo.path[0] == fromToken) {
            path = pairInfo.path;
        } else {
            for (uint index = 0; index < pairInfo.path.length; index++) {
                path[index] = (pairInfo.path[pairInfo.path.length - 1 - index]);
            }
        }
    }
}