// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0 <0.9.0;

import {IWETH} from "./interfaces/IWETH.sol";
import "./interfaces/Uniswap.sol";
import {SafeTransferLib} from "./lib/SafeTransferLib.sol";

// ZZZZZZZZZZZZZZZZZZZ
// Z:::::::::::::::::Z
// Z:::::::::::::::::Z
// Z:::ZZZZZZZZ:::::Z
// ZZZZZ     Z:::::Z      eeeeeeeeeeee    uuuuuu    uuuuuu      ssssssssss
//         Z:::::Z      ee::::::::::::ee  u::::u    u::::u    ss::::::::::s
//        Z:::::Z      e::::::eeeee:::::eeu::::u    u::::u  ss:::::::::::::s
//       Z:::::Z      e::::::e     e:::::eu::::u    u::::u  s::::::ssss:::::s
//      Z:::::Z       e:::::::eeeee::::::eu::::u    u::::u   s:::::s  ssssss
//     Z:::::Z        e:::::::::::::::::e u::::u    u::::u     s::::::s
//    Z:::::Z         e::::::eeeeeeeeeee  u::::u    u::::u        s::::::s
// ZZZ:::::Z     ZZZZZe:::::::e           u:::::uuuu:::::u  ssssss   s:::::s
// Z::::::ZZZZZZZZ:::Ze::::::::e          u:::::::::::::::uus:::::ssss::::::s
// Z:::::::::::::::::Z e::::::::eeeeeeee   u:::::::::::::::us::::::::::::::s
// Z:::::::::::::::::Z  ee:::::::::::::e    uu::::::::uu:::u s:::::::::::ss
// ZZZZZZZZZZZZZZZZZZZ    eeeeeeeeeeeeee      uuuuuuuu  uuuu  sssssssssss

library BalanceDeltaLibrary {
    function amount0(int256 balanceDelta) internal pure returns (int128 _amount0) {
        assembly ("memory-safe") {
            _amount0 := sar(128, balanceDelta)
        }
    }

    function amount1(int256 balanceDelta) internal pure returns (int128 _amount1) {
        assembly ("memory-safe") {
            _amount1 := signextend(15, balanceDelta)
        }
    }
}

contract ZeusSwapDelegator {
    using BalanceDeltaLibrary for int256;

    address internal constant ETH = address(0);

    address public immutable WETH;
    address public immutable V4_POOL_MANAGER;
    address public immutable UNISWAP_V3_FACTORY;
    address public immutable PANCAKE_SWAP_V3_FACTORY;

    struct DeployParams {
        address weth;
        address v4PoolManager;
        address uniswapV3Factory;
        address pancakeSwapV3Factory;
    }

    constructor(DeployParams memory params) {
        WETH = params.weth;
        V4_POOL_MANAGER = params.v4PoolManager;
        UNISWAP_V3_FACTORY = params.uniswapV3Factory;
        PANCAKE_SWAP_V3_FACTORY = params.pancakeSwapV3Factory;
    }

    // Commands
    bytes1 constant V2_SWAP = 0x01;
    bytes1 constant V3_SWAP = 0x02;
    bytes1 constant V4_SWAP = 0x03;
    bytes1 constant WRAP_ETH = 0x04;
    bytes1 constant UNWRAP_WETH = 0x05;
    bytes1 constant WRAP_ETH_NO_CHECK = 0x06;

    // Inputs

    struct ZParams {
        bytes commands;
        bytes[] inputs;
        address currencyOut;
        uint256 amountMin;
    }

    /// @notice Parameters for a V2/V3 swap
    /// @param amountIn The amount of tokenIn to swap
    /// @param tokenIn The input token
    /// @param tokenOut The output token
    /// @param pool The pool to swap on
    /// @param poolVariant 0x00 for V2, 0x01 for V3
    /// @param fee The pool fee in hundredths of bips (eg. 3000 for 0.3%)
    struct V2V3SwapParams {
        uint256 amountIn;
        address tokenIn;
        address tokenOut;
        address pool;
        bytes1 poolVariant;
        uint24 fee;
    }

    /// @notice Parameters for a V4 swap
    /// @param currencyIn The input currency (address(0) for ETH)
    /// @param currencyOut The output currency (address(0) for ETH)
    /// @param amountIn The amount of currencyIn to swap
    /// @param fee The pool fee in hundredths of bips (eg. 3000 for 0.3%)
    /// @param tickSpacing The tick spacing of the pool
    /// @param zeroForOne Whether the swap is from currencyIn to currencyOut
    /// @param hooks The hooks to use for the swap
    /// @param hookData The data to pass to the hooks
    /// @param recipient The address to receive the output currency, must be the same as msg.sender
    struct V4SwapArgs {
        address currencyIn;
        address currencyOut;
        uint256 amountIn;
        uint24 fee;
        int24 tickSpacing;
        bool zeroForOne;
        address hooks;
        bytes hookData;
        address recipient;
    }

    struct V4CallBackData {
        address currencyIn;
        address currencyOut;
        uint256 amountIn;
        uint24 fee;
        int24 tickSpacing;
        bool zeroForOne;
        address hooks;
        bytes hookData;
        address recipient;
    }

    struct WrapETH {
        uint256 amountMin;
    }

    struct WrapETHNoCheck {
        uint256 amount;
    }

    struct UnwrapWETH {
        uint256 amountMin;
    }

    function zSwap(ZParams calldata params) public payable {
        require(msg.sender == address(this), "Only callable by self");

        // Keep track of the eth/weth balances before the swap

        uint256 balanceBefore;
        uint256 ethBalanceBefore = 0;
        uint256 wethBalanceBefore = 0;

        if (params.currencyOut == ETH) {
            balanceBefore = msg.sender.balance;
        } else {
            balanceBefore = SafeTransferLib.balanceOf(params.currencyOut, msg.sender);
        }

        (bool trackEth, bool trackWeth) = shouldTrackEthWethBalances(params.commands);

        if (trackEth) {
            if (params.currencyOut == ETH) {
                ethBalanceBefore = balanceBefore;
            } else {
                ethBalanceBefore = msg.sender.balance;
            }
        }

        if (trackWeth) {
            if (params.currencyOut == WETH) {
                wethBalanceBefore = balanceBefore;
            } else {
                wethBalanceBefore = SafeTransferLib.balanceOf(WETH, msg.sender);
            }
        }

        execute(params, ethBalanceBefore, wethBalanceBefore);

        uint256 balanceAfter;
        if (params.currencyOut == ETH) {
            balanceAfter = msg.sender.balance;
        } else {
            balanceAfter = SafeTransferLib.balanceOf(params.currencyOut, msg.sender);
        }

        require(balanceAfter > balanceBefore, "Bad Swap: No amount received");

        uint256 realAmountOut = balanceAfter - balanceBefore;
        require(realAmountOut >= params.amountMin, "SlippageCheck: Insufficient output");
    }

    /// @notice Executes a series of commands with their corresponding inputs.
    function execute(ZParams calldata params, uint256 ethBalanceBefore, uint256 wethBalanceBefore) internal {
        for (uint256 i = 0; i < params.commands.length; i++) {
            bytes1 command = params.commands[i];
            bytes memory input = params.inputs[i];

            bool isValid = command >= V2_SWAP && command <= WRAP_ETH_NO_CHECK;
            require(isValid, "Invalid command");

            if (command == V2_SWAP || command == V3_SWAP) {
                _swapV2V3(input);
            }

            if (command == V4_SWAP) {
                _swapV4(input);
            }

            if (command == WRAP_ETH) {
                wrapETH(input, ethBalanceBefore);
            }

            if (command == UNWRAP_WETH) {
                unwrapWETH(input, wethBalanceBefore);
            }

            if (command == WRAP_ETH_NO_CHECK) {
                wrapETHNoCheck(input);
            }
        }
    }

    function shouldTrackEthWethBalances(bytes calldata commands) internal pure returns (bool, bool) {
        bool trackEth = false;
        bool trackWeth = false;

        for (uint256 i = 0; i < commands.length; i++) {
            bytes1 command = commands[i];

            if (command == WRAP_ETH) {
                trackEth = true;
            }

            if (command == UNWRAP_WETH) {
                trackWeth = true;
            }
        }

        return (trackEth, trackWeth);
    }

    function _swapV2V3(bytes memory input) internal {
        V2V3SwapParams memory params = abi.decode(input, (V2V3SwapParams));

        if (params.poolVariant == 0x00) {
            OnUniswapV2(params);
        } else if (params.poolVariant == 0x01) {
            OnUniswapV3(params);
        } else {
            revert("Invalid pool variant");
        }
    }

    function _swapV4(bytes memory input) internal {
        IV4PoolManager(V4_POOL_MANAGER).unlock(input);
    }

    /// @notice Wraps ETH into WETH
    /// @notice Use as a withdrawal method, must be the last command
    function wrapETH(bytes memory input, uint256 ethBalanceBefore) internal {
        WrapETH memory params = abi.decode(input, (WrapETH));
        uint256 ethBalanceAfter = msg.sender.balance;
        uint256 realAmount = ethBalanceAfter - ethBalanceBefore;
        require(realAmount >= params.amountMin, "SlippageCheck: Insufficient ETH");
        IWETH(WETH).deposit{value: realAmount}();
    }

    /// @notice Wraps ETH to WETH (No slippage check)
    /// @notice Use as a deposit method, must be the first command
    function wrapETHNoCheck(bytes memory input) internal {
        WrapETHNoCheck memory params = abi.decode(input, (WrapETHNoCheck));
        IWETH(WETH).deposit{value: params.amount}();
    }

    /// @notice Unwraps WETH to ETH
    /// @notice Use as a withdrawal method, must be the last command
    function unwrapWETH(bytes memory input, uint256 wethBalanceBefore) internal {
        UnwrapWETH memory params = abi.decode(input, (UnwrapWETH));
        uint256 wethBalanceAfter = SafeTransferLib.balanceOf(WETH, msg.sender);
        uint256 realAmount = wethBalanceAfter - wethBalanceBefore;
        require(realAmount >= params.amountMin, "SlippageCheck: Insufficient WETH");
        IWETH(WETH).withdraw(realAmount);
    }

    /// @notice Callback for Uniswap V3 swaps.
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        (address tokenIn, address tokenOut, uint256 amountIn, uint24 fee) = abi.decode(
            data,
            (address, address, uint256, uint24)
        );
        bool zeroForOne = tokenIn < tokenOut;

        address pool = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(tokenIn, tokenOut, fee);
        require(msg.sender == pool && pool != address(0), "UniswapV3SwapCallback: Msg.sender is not a pool");

        uint256 amountToPay = zeroForOne ? uint256(amount0Delta) : uint256(amount1Delta);
        require(amountToPay == amountIn, "UniswapV3SwapCallback: amountToPay != amountIn");

        SafeTransferLib.safeTransfer(tokenIn, pool, amountToPay);
    }

    /// @notice Callback for Pancake V3 swaps.
    function pancakeV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        (address tokenIn, address tokenOut, uint256 amountIn, uint24 fee) = abi.decode(
            data,
            (address, address, uint256, uint24)
        );
        bool zeroForOne = tokenIn < tokenOut;

        address pool = IUniswapV3Factory(PANCAKE_SWAP_V3_FACTORY).getPool(tokenIn, tokenOut, fee);
        require(msg.sender == pool && pool != address(0), "PancakeV3SwapCallback: Msg.sender is not a pool");

        uint256 amountToPay = zeroForOne ? uint256(amount0Delta) : uint256(amount1Delta);
        require(amountToPay == amountIn, "PancakeV3SwapCallback: amountToPay != amountIn");

        SafeTransferLib.safeTransfer(tokenIn, pool, amountToPay);
    }

    /// @notice Callback for Uniswap V4 swaps.
    function unlockCallback(bytes calldata callbackData) public payable returns (bytes memory result) {
        require(msg.sender == V4_POOL_MANAGER, "UniswapV4SwapCallback: Msg.sender is not PoolManager");

        V4SwapArgs memory data = abi.decode(callbackData, (V4SwapArgs));

        (uint256 amountOut, uint256 amountToPay) = _swap(data);
        IV4PoolManager poolManager = IV4PoolManager(V4_POOL_MANAGER);

        // Settle input
        if (data.currencyIn == ETH) {
            poolManager.settle{value: amountToPay}();
        } else {
            SafeTransferLib.safeTransfer(data.currencyIn, V4_POOL_MANAGER, amountToPay);
            poolManager.settle();
        }

        poolManager.take(data.currencyOut, data.recipient, amountOut);

        return "";
    }

    function _swap(V4SwapArgs memory data) internal returns (uint256 amountOut, uint256 amountToPay) {
        (address currency0, address currency1) = sortCurrencies(data.currencyIn, data.currencyOut);

        V4PoolKey memory poolKey = V4PoolKey(currency0, currency1, data.fee, data.tickSpacing, data.hooks);

        uint160 sqrtPriceLimitX96 = data.zeroForOne ? MIN_SQRT_RATIO : MAX_SQRT_RATIO;
        V4SwapParams memory swapParams = V4SwapParams(data.zeroForOne, -int256(data.amountIn), sqrtPriceLimitX96);

        IV4PoolManager poolManager = IV4PoolManager(V4_POOL_MANAGER);

        int256 delta = poolManager.swap(poolKey, swapParams, data.hookData);
        poolManager.sync(data.currencyIn);

        int128 inputDelta = data.zeroForOne ? delta.amount0() : delta.amount1();
        require(inputDelta < 0, "V4: Positive input delta");

        amountToPay = uint256(uint128(-inputDelta));
        require(amountToPay == data.amountIn, "V4: amountToPay != amountIn");

        int128 outputDelta = data.zeroForOne ? delta.amount1() : delta.amount0();
        require(outputDelta > 0, "V4: Negative output delta");

        amountOut = uint256(uint128(outputDelta));

        return (amountOut, amountToPay);
    }

    function sortCurrencies(address currencyA, address currencyB) internal pure returns (address, address) {
        if (currencyA < currencyB) {
            return (currencyA, currencyB);
        } else {
            return (currencyB, currencyA);
        }
    }

    uint160 internal constant MIN_SQRT_RATIO = 4295128749;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970341;

    function OnUniswapV2(V2V3SwapParams memory params) internal {
        uint reserveIn;
        uint reserveOut;

        SafeTransferLib.safeTransfer(params.tokenIn, params.pool, params.amountIn);

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

        IUniswapV2Pair(params.pool).swap(amount0Out, amount1Out, msg.sender, new bytes(0));
    }

    function OnUniswapV3(V2V3SwapParams memory params) internal {
        bool zeroForOne = params.tokenIn < params.tokenOut;
        uint160 sqrtPriceLimitX96 = zeroForOne ? MIN_SQRT_RATIO : MAX_SQRT_RATIO;

        IUniswapV3Pool(params.pool).swap(
            msg.sender,
            zeroForOne,
            int256(params.amountIn),
            sqrtPriceLimitX96,
            abi.encode(params.tokenIn, params.tokenOut, params.amountIn, params.fee)
        );
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

    receive() external payable {}
}
