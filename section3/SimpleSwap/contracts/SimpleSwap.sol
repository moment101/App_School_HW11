// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ISimpleSwap } from "./interface/ISimpleSwap.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import "forge-std/Test.sol";

contract SimpleSwap is ISimpleSwap, ERC20 {
    using Address for address;

    address private _tokenA;
    address private _tokenB;
    uint private _reserveA;
    uint private _reserveB;
    ERC20 i_tokenA;
    ERC20 i_tokenB;

    error AddressPairError();

    // Implement core logic here
    constructor(address tokenA, address tokenB) ERC20("SimpleSwap", "SUI") {
        require(tokenA.isContract(), "SimpleSwap: TOKENA_IS_NOT_CONTRACT");
        require(tokenB.isContract(), "SimpleSwap: TOKENB_IS_NOT_CONTRACT");
        require(tokenA != tokenB, "SimpleSwap: TOKENA_TOKENB_IDENTICAL_ADDRESS");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        _tokenA = token0;
        _tokenB = token1;
        i_tokenA = ERC20(_tokenA);
        i_tokenB = ERC20(_tokenB);
    }

    /// @notice Swap tokenIn for tokenOut with amountIn
    /// @param tokenIn The address of the token to swap from
    /// @param tokenOut The address of the token to swap to
    /// @param amountIn The amount of tokenIn to swap
    /// @return amountOut The amount of tokenOut received
    function swap(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut) {
        require(tokenIn == _tokenA || tokenIn == _tokenB, "SimpleSwap: INVALID_TOKEN_IN");
        require(tokenOut == _tokenA || tokenOut == _tokenB, "SimpleSwap: INVALID_TOKEN_OUT");
        require(tokenIn != tokenOut, "SimpleSwap: IDENTICAL_ADDRESS");
        require(amountIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");

        /*
        _reserveA * _reserveB = K
        ( _reserveA + amountIn ) * ( _reserveB - amountOut) = _reserveA * _reserveB
        _reserveB - amountOut = ( _reserveA * _reserveB ) / ( _reserveA + amountIn )
        amountOut = _reserveB - ( _reserveA * _reserveB ) / ( _reserveA + amountIn )

        ceil(( _reserveA * _reserveB ) / ( _reserveA + amountIn ))
        --->
        假設原本是整除，那 -1 之後會讓它答案小 1，再 +1 後就變回原本的值
        假設原本不整除，那 -1 不會對值造成影響，再 +1 後就變回比原本大 1 的值
        from billh

        ( _reserveA * _reserveB - 1 ) / ( _reserveA + amountIn )   +    1
        */

        if (tokenIn == _tokenA && tokenOut == _tokenB) {
            amountOut = _reserveB - ((_reserveA * _reserveB - 1) / (_reserveA + amountIn) + 1);
            i_tokenA.transferFrom(msg.sender, address(this), amountIn);
            i_tokenB.transfer(msg.sender, amountOut);
            _reserveA += amountIn;
            _reserveB -= amountOut;
            emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
        } else if (tokenIn == _tokenB && tokenOut == _tokenA) {
            amountOut = _reserveA - ((_reserveA * _reserveB - 1) / (_reserveB + amountIn) + 1);
            i_tokenA.transfer(msg.sender, amountOut);
            i_tokenB.transferFrom(msg.sender, address(this), amountIn);
            _reserveA -= amountOut;
            _reserveB += amountIn;
            emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
        } else {
            revert AddressPairError();
        }
    }

    /// @notice Add liquidity to the pool
    /// @param amountAIn The amount of tokenA to add
    /// @param amountBIn The amount of tokenB to add
    /// @return amountA The actually amount of tokenA added
    /// @return amountB The actually amount of tokenB added
    /// @return liquidity The amount of liquidity minted
    function addLiquidity(
        uint256 amountAIn,
        uint256 amountBIn
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(amountAIn > 0 && amountBIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        if (totalSupply() == 0) {
            liquidity = Math.sqrt(amountAIn * amountBIn);

            amountA = amountAIn;
            amountB = amountBIn;

            i_tokenA.transferFrom(msg.sender, address(this), amountAIn);
            i_tokenB.transferFrom(msg.sender, address(this), amountBIn);

            _reserveA += amountA;
            _reserveB += amountB;

            _mint(msg.sender, liquidity);
            emit AddLiquidity(msg.sender, amountAIn, amountBIn, liquidity);
        } else {
            liquidity = Math.min((amountAIn * totalSupply()) / _reserveA, (amountBIn * totalSupply()) / _reserveB);

            amountA = (liquidity * _reserveA) / totalSupply();
            amountB = (liquidity * _reserveB) / totalSupply();

            i_tokenA.transferFrom(msg.sender, address(this), amountA);
            i_tokenB.transferFrom(msg.sender, address(this), amountB);

            _reserveA += amountA;
            _reserveB += amountB;

            _mint(msg.sender, liquidity);
            emit AddLiquidity(msg.sender, amountA, amountB, liquidity);
        }
    }

    /// @notice Remove liquidity from the pool
    /// @param liquidity The amount of liquidity to remove
    /// @return amountA The amount of tokenA received
    /// @return amountB The amount of tokenB received
    function removeLiquidity(uint256 liquidity) external returns (uint256 amountA, uint256 amountB) {
        require(liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED");

        amountA = (liquidity * _reserveA) / totalSupply();
        amountB = (liquidity * _reserveB) / totalSupply();
        i_tokenA.transfer(msg.sender, amountA);
        i_tokenB.transfer(msg.sender, amountB);

        _burn(msg.sender, liquidity);
        emit Transfer(address(this), address(0), liquidity);
        emit RemoveLiquidity(msg.sender, amountA, amountB, liquidity);
    }

    /// @notice Get the reserves of the pool
    /// @return reserveA The reserve of tokenA
    /// @return reserveB The reserve of tokenB
    function getReserves() external view returns (uint256 reserveA, uint256 reserveB) {
        return (_reserveA, _reserveB);
    }

    /// @notice Get the address of tokenA
    /// @return tokenA The address of tokenA
    function getTokenA() external view returns (address tokenA) {
        return _tokenA;
    }

    /// @notice Get the address of tokenB
    /// @return tokenB The address of tokenB
    function getTokenB() external view returns (address tokenB) {
        return _tokenB;
    }
}
