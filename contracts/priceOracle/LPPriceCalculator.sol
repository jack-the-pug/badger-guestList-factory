// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import '../libraries/HomoraMath.sol';
import '../interfaces/IUniv2LikePair.sol';
import '../interfaces/IPriceCalculator.sol';
import '../interfaces/IPriceFeed.sol';

contract LPPriceCalculator is IPriceFeed {
    using SafeMath for uint256;
    using HomoraMath for uint256;

    address public immutable priceCalculatorAddress;

    constructor(address _priceCalculatorAddress) {
        priceCalculatorAddress = _priceCalculatorAddress;
    }

    function getData(address pair) external view override returns (uint256) {
        address token0 = IUniv2LikePair(pair).token0();
        address token1 = IUniv2LikePair(pair).token1();
        uint totalSupply = IUniv2LikePair(pair).totalSupply();
        (uint r0, uint r1, ) = IUniv2LikePair(pair).getReserves();

        uint sqrtK = HomoraMath.sqrt(r0.mul(r1)).fdiv(totalSupply);  // in 2**112
        uint px0 = IPriceCalculator(priceCalculatorAddress).tokenPriceInUSD(token0, 1e18);
        uint px1 = IPriceCalculator(priceCalculatorAddress).tokenPriceInUSD(token1, 1e18);
        uint fairPriceInUSD = sqrtK.mul(2).mul(HomoraMath.sqrt(px0)).div(2**56).mul(HomoraMath.sqrt(px1)).div(2**56);

        return fairPriceInUSD;
    }
}
