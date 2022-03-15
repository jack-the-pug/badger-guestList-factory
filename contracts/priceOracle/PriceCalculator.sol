// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import '../interfaces/IPriceFeed.sol';

// ALL decimal will scale to 1e18
contract PriceCalculator is Initializable, OwnableUpgradeable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct PriceFeed {
        address oracleAddress;
        address onChainFetcher;
    }

    mapping(address => PriceFeed) public tokenPriceFeed;

    function initialize() external initializer {
        __Ownable_init();
    }

    function addFeeds(address[] memory tokens, PriceFeed[] memory priceFeeds) external onlyOwner {
        require(tokens.length == priceFeeds.length, "bad_args");

        for (uint256 i = 0; i < tokens.length; i++ ) {
            tokenPriceFeed[tokens[i]] = priceFeeds[i];
        }
    }

    function oracleValueOf(address oracleAddress, address tokenAddress, uint amount) internal view returns (uint256 valueInUSD) {
        uint256 price = IPriceFeed(oracleAddress).getData(tokenAddress);
        valueInUSD = price.mul(amount).div(10 ** IERC20Metadata(tokenAddress).decimals());
    }

    function tokenPriceInUSD(address tokenAddress, uint amount) view external returns (uint256 price) {
        PriceFeed storage feed = tokenPriceFeed[tokenAddress];

        require(feed.oracleAddress != address(0) || feed.onChainFetcher != address(0), "no_price_feed");
        uint256 pairPrice = 0;
        uint256 oraclePrice = 0;

        if (feed.onChainFetcher != address(0)) {
            pairPrice = oracleValueOf(feed.onChainFetcher, tokenAddress, amount);
        }

        if (feed.oracleAddress != address(0)) {
            oraclePrice = oracleValueOf(feed.oracleAddress, tokenAddress, amount);
        }

        if (feed.onChainFetcher == address(0)) {
            return oraclePrice;
        }

        if (feed.oracleAddress == address(0)) {
            return pairPrice;
        }

        return Math.min(oraclePrice, pairPrice);
    }

}

