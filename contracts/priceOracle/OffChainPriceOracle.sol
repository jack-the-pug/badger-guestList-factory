// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import '../interfaces/IPriceFeed.sol';

contract OffChainPriceOracle is Ownable, IPriceFeed {

    mapping(address => uint256) tokenPriceInUSD;

    function update(address[] memory token, uint256[] memory price) external onlyOwner {
        require(token.length == price.length);
        uint256 len = token.length;

        for (uint256 i = 0; i < len; ++i) {
            tokenPriceInUSD[token[i]] = price[i];
        }
    }

    function getData(address token) external view override returns(uint256) {
        return tokenPriceInUSD[token];
    }

}