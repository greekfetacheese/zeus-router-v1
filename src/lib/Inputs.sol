// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

import {IPermit2} from "../interfaces/IPermit2.sol";

library Inputs {
    struct Permit2Permit {
        IPermit2.PermitSingle permitSingle;
        bytes signature;
    }

    /// @notice Parameters for a V2/V3 swap
    /// @param amountIn The amount of tokenIn to swap
    /// @param tokenIn The input token
    /// @param tokenOut The output token
    /// @param pool The pool to swap on
    /// @param poolVariant 0 for V2, 1 for V3
    /// @param recipient The recipient of the tokenOut
    /// @param fee The pool fee in hundredths of bips (eg. 3000 for 0.3%)
    /// @param permit2 Whether the funds should come from permit or are already in the router
    struct V2V3SwapParams {
        uint256 amountIn;
        uint256 amountOutMin;
        address tokenIn;
        address tokenOut;
        address pool;
        uint poolVariant;
        address recipient;
        uint24 fee;
        bool permit2;
    }


    /// @notice Parameters for a V4 swap
    /// @param currencyIn The input currency (address(0) for ETH)
    /// @param currencyOut The output currency (address(0) for ETH)
    /// @param amountIn The amount of currencyIn to swap
    /// @param amountOutMin The minimum amount of currencyOut to receive
    /// @param fee The pool fee in hundredths of bips (eg. 3000 for 0.3%)
    /// @param tickSpacing The tick spacing of the pool
    /// @param zeroForOne Whether the swap is from currencyIn to currencyOut
    /// @param hooks The hooks to use for the swap
    /// @param hookData The data to pass to the hooks
    /// @param recipient The recipient of the currencyOut
    /// @param permit2 Whether the funds should come from permit or are already in the router
    struct V4SwapParams {
        address currencyIn;
        address currencyOut;
        uint256 amountIn;
        uint256 amountOutMin;
        uint24 fee;
        int24 tickSpacing;
        bool zeroForOne;
        address hooks;
        bytes hookData;
        address recipient;
        bool permit2;
    }

    /// @notice WrapETH
    /// @param recipient The recipient of the wrapped ETH
    /// @param amount The amount of ETH to wrap
    struct WrapETH {
        address recipient;
        uint256 amount;
    }

    /// @notice UnwrapWETH
    /// @param recipient The recipient of the unwrapped ETH
    /// @param amountMin The minimum amount of ETH to unwrap
    struct UnwrapWETH {
        address recipient;
        uint256 amountMin;
    }

    /// @notice Sweep
    /// @param currency The currency to sweep, Use address(0) for ETH
    /// @param recipient The recipient of the tokens
    /// @param amountMin The minimum amount of tokens to sweep
    struct Sweep {
        address currency;
        address recipient;
        uint256 amountMin;
    }
}
