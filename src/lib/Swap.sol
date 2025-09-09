// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0 <0.9.0;

import {Inputs} from "./Inputs.sol";
import {IUniswapV3Pool, IUniswapV2Pair, IV4PoolManager} from "../interfaces/Uniswap.sol";

library Swap {

    uint160 internal constant MIN_SQRT_RATIO = 4295128749;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970341;

    struct V4CallBackData {
        address payer;
        Inputs.V4SwapParams params;
    }

    function OnUniswapV2(Inputs.V2V3SwapParams memory params) internal {

        uint reserveIn;
        uint reserveOut;

        {
            (uint reserve0, uint reserve1, ) = IUniswapV2Pair(params.pool).getReserves();

            // sort reserves
            if (params.tokenIn < params.tokenOut) {
                reserveIn = reserve0;
                reserveOut = reserve1;
            } else {
                reserveIn = reserve1;
                reserveOut = reserve0;
            }
        }

        uint256 amountOut = getAmountOut(params.amountIn, reserveIn, reserveOut, params.fee);

        (uint amount0Out, uint amount1Out) = params.tokenIn < params.tokenOut
            ? (uint(0), amountOut)
            : (amountOut, uint(0));

        IUniswapV2Pair(params.pool).swap(amount0Out, amount1Out, params.recipient, new bytes(0));
    }

    function OnUniswapV3(Inputs.V2V3SwapParams memory params, address payer) internal {
        bool zeroForOne = params.tokenIn < params.tokenOut;
        uint160 sqrtPriceLimitX96 = zeroForOne ? MIN_SQRT_RATIO : MAX_SQRT_RATIO;

        IUniswapV3Pool(params.pool).swap(
            params.recipient,
            zeroForOne,
            int256(params.amountIn),
            sqrtPriceLimitX96,
            abi.encode(params.tokenIn, params.tokenOut, params.amountIn, payer, params.fee, params.permit2)
        );
    }

    function OnUniswapV4(Inputs.V4SwapParams memory params, address payer, address poolManager) internal {
        V4CallBackData memory data = V4CallBackData(payer, params);
        IV4PoolManager(poolManager).unlock(abi.encode(data));
    }

    function getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut,
        uint poolfee
    ) internal pure returns (uint amountOut) {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint fee = (10000 - poolfee / 100) / 10;
        uint amountInWithFee = amountIn * fee;
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
