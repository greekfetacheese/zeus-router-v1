// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0 <0.9.0;

import {IWETH} from "./interfaces/IWETH.sol";
import {IUniswapV3Factory, IV4PoolManager, V4SwapParams, V4PoolKey} from "./interfaces/Uniswap.sol";
import {Swap} from "./lib/Swap.sol";
import {IPermit2} from "./interfaces/IPermit2.sol";
import {Commands} from "./lib/Commands.sol";
import {Inputs} from "./lib/Inputs.sol";
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

contract ZeusRouter {
    using BalanceDeltaLibrary for int256;

    address internal constant ETH = address(0);

    address public immutable WETH;
    address public immutable PERMIT2;
    address public immutable V4_POOL_MANAGER;
    address public immutable UNISWAP_V3_FACTORY;
    address public immutable PANCAKE_SWAP_V3_FACTORY;

    struct DeployParams {
        address weth;
        address permit2;
        address v4PoolManager;
        address uniswapV3Factory;
        address pancakeSwapV3Factory;
    }

    constructor(DeployParams memory params) {
        WETH = params.weth;
        PERMIT2 = params.permit2;
        V4_POOL_MANAGER = params.v4PoolManager;
        UNISWAP_V3_FACTORY = params.uniswapV3Factory;
        PANCAKE_SWAP_V3_FACTORY = params.pancakeSwapV3Factory;
    }

    /// @notice Executes a series of commands with their corresponding inputs.
    function execute(bytes calldata commands, bytes[] calldata inputs) public payable {
        for (uint256 i = 0; i < commands.length; i++) {
            bytes1 command = commands[i];
            bytes memory input = inputs[i];

            bool isValid = command >= Commands.PERMIT2_PERMIT && command <= Commands.SWEEP;
            require(isValid, "Invalid command");

            if (command == Commands.PERMIT2_PERMIT) {
                Inputs.Permit2Permit memory params = abi.decode(input, (Inputs.Permit2Permit));
                IPermit2(PERMIT2).permit(msg.sender, params.permitSingle, params.signature);
            }

            if (command == Commands.V2_SWAP) {
                _swapV2V3(input);
            }

            if (command == Commands.V3_SWAP) {
                _swapV2V3(input);
            }

            if (command == Commands.V4_SWAP) {
                _swapV4(input);
            }

            if (command == Commands.WRAP_ETH) {
                wrapETH(input);
            }

            if (command == Commands.UNWRAP_WETH) {
                unwrapWETH(input);
            }

            if (command == Commands.SWEEP) {
                sweep(input);
            }
        }
    }

    function _swapV2V3(bytes memory input) internal {
        Inputs.V2V3SwapParams memory params = abi.decode(input, (Inputs.V2V3SwapParams));

        uint256 balanceBefore = SafeTransferLib.balanceOf(params.tokenOut, params.recipient);

        if (params.poolVariant == 0) {
            if (params.permit2) {
                IPermit2(PERMIT2).transferFrom(msg.sender, params.pool, uint160(params.amountIn), params.tokenIn);
            } else {
                SafeTransferLib.safeTransfer(params.tokenIn, params.pool, params.amountIn);
            }

            Swap.OnUniswapV2(params);
        } else if (params.poolVariant == 1) {
            Swap.OnUniswapV3(params, msg.sender);
        } else {
            revert("Invalid pool variant");
        }

        uint256 balanceAfter = SafeTransferLib.balanceOf(params.tokenOut, params.recipient);

        require(balanceAfter > balanceBefore, "Bad Swap: No amount received");

        uint256 realAmountOut = balanceAfter - balanceBefore;
        require(realAmountOut >= params.amountOutMin, "SlippageCheck: Insufficient output");
    }

    function _swapV4(bytes memory input) internal {
        Inputs.V4SwapParams memory params = abi.decode(input, (Inputs.V4SwapParams));

        uint256 balanceBefore;
        if (params.currencyOut == ETH) {
            balanceBefore = params.recipient.balance;
        } else {
            balanceBefore = SafeTransferLib.balanceOf(params.currencyOut, params.recipient);
        }

        Swap.OnUniswapV4(params, msg.sender, V4_POOL_MANAGER);

        uint256 balanceAfter;
        if (params.currencyOut == ETH) {
            balanceAfter = params.recipient.balance;
        } else {
            balanceAfter = SafeTransferLib.balanceOf(params.currencyOut, params.recipient);
        }

        require(balanceAfter > balanceBefore, "Bad Swap: No amount received");

        uint256 realAmountOut = balanceAfter - balanceBefore;
        require(realAmountOut >= params.amountOutMin, "SlippageCheck: Insufficient output");
    }

    /// @notice Wraps ETH into WETH
    function wrapETH(bytes memory input) internal {
        Inputs.WrapETH memory params = abi.decode(input, (Inputs.WrapETH));
        IWETH(WETH).deposit{value: params.amount}();

        if (params.recipient != address(this)) {
            SafeTransferLib.safeTransfer(WETH, params.recipient, params.amount);
        }
    }

    /// @notice Unwraps all WETH from the contract to the recipient
    function unwrapWETH(bytes memory input) internal {
        Inputs.UnwrapWETH memory params = abi.decode(input, (Inputs.UnwrapWETH));
        uint256 balance = SafeTransferLib.balanceOf(WETH, address(this));
        require(balance >= params.amountMin, "SlippageCheck: Insufficient WETH");

        IWETH(WETH).withdraw(balance);

        if (params.recipient != address(this)) {
            SafeTransferLib.forceSafeTransferETH(params.recipient, balance);
        }
    }

    /// @notice Sweeps all of the contract's ERC20 or ETH to the recipient
    function sweep(bytes memory input) internal {
        Inputs.Sweep memory params = abi.decode(input, (Inputs.Sweep));
        uint256 balance;
        if (params.currency == ETH) {
            balance = address(this).balance;
            require(balance >= params.amountMin, "SlippageCheck: Insufficient ETH");
            SafeTransferLib.forceSafeTransferETH(params.recipient, balance);
        } else {
            balance = SafeTransferLib.balanceOf(params.currency, address(this));
            require(balance >= params.amountMin, "SlippageCheck: Insufficient token balance");
            SafeTransferLib.safeTransfer(params.currency, params.recipient, balance);
        }
    }

    /// @notice Callback for Uniswap V3 swaps.
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        (address tokenIn, address tokenOut, uint256 amountIn, address payer, uint24 fee, bool permit2) = abi.decode(
            data,
            (address, address, uint256, address, uint24, bool)
        );
        bool zeroForOne = tokenIn < tokenOut;

        address pool = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(tokenIn, tokenOut, fee);
        require(msg.sender == pool && pool != address(0), "UniswapV3SwapCallback: Msg.sender is not a pool");

        uint256 amountToPay = zeroForOne ? uint256(amount0Delta) : uint256(amount1Delta);
        require(amountToPay == amountIn, "UniswapV3SwapCallback: amountToPay != amountIn");

        if (permit2) {
            IPermit2(PERMIT2).transferFrom(payer, pool, uint160(amountToPay), tokenIn);
        } else {
            SafeTransferLib.safeTransfer(tokenIn, pool, amountToPay);
        }
    }

    /// @notice Callback for Pancake V3 swaps.
    function pancakeV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        (address tokenIn, address tokenOut, uint256 amountIn, address payer, uint24 fee, bool permit2) = abi.decode(
            data,
            (address, address, uint256, address, uint24, bool)
        );
        bool zeroForOne = tokenIn < tokenOut;

        // Verify caller is the correct pool
        address pool = IUniswapV3Factory(PANCAKE_SWAP_V3_FACTORY).getPool(tokenIn, tokenOut, fee);
        require(msg.sender == pool && pool != address(0), "PancakeV3SwapCallback: Msg.sender is not a pool");

        uint256 amountToPay = zeroForOne ? uint256(amount0Delta) : uint256(amount1Delta);
        require(amountToPay == amountIn, "PancakeV3SwapCallback: amountToPay != amountIn");

        if (permit2) {
            IPermit2(PERMIT2).transferFrom(payer, pool, uint160(amountToPay), tokenIn);
        } else {
            SafeTransferLib.safeTransfer(tokenIn, pool, amountToPay);
        }
    }

    /// @notice Callback for Uniswap V4 swaps.
    function unlockCallback(bytes calldata callbackData) public payable returns (bytes memory result) {
        require(msg.sender == V4_POOL_MANAGER, "UniswapV4SwapCallback: Msg.sender is not PoolManager");

        Swap.V4CallBackData memory data = abi.decode(callbackData, (Swap.V4CallBackData));

        (uint256 amountOut, uint256 amountToPay) = _swap(data);
        IV4PoolManager poolManager = IV4PoolManager(V4_POOL_MANAGER);

        // Settle input
        if (data.params.currencyIn == ETH) {
            poolManager.settle{value: amountToPay}();
        } else {
            if (data.params.permit2) {
                IPermit2(PERMIT2).transferFrom(
                    data.payer,
                    V4_POOL_MANAGER,
                    uint160(amountToPay),
                    data.params.currencyIn
                );
            } else {
                SafeTransferLib.safeTransfer(data.params.currencyIn, V4_POOL_MANAGER, amountToPay);
            }
            poolManager.settle();
        }

        poolManager.take(data.params.currencyOut, data.params.recipient, amountOut);

        return "";
    }

    function _swap(Swap.V4CallBackData memory data) internal returns (uint256 amountOut, uint256 amountToPay) {
        (address currency0, address currency1) = sortCurrencies(data.params.currencyIn, data.params.currencyOut);

        V4PoolKey memory poolKey = V4PoolKey(
            currency0,
            currency1,
            data.params.fee,
            data.params.tickSpacing,
            data.params.hooks
        );

        uint160 sqrtPriceLimitX96 = data.params.zeroForOne ? Swap.MIN_SQRT_RATIO : Swap.MAX_SQRT_RATIO;
        V4SwapParams memory swapParams = V4SwapParams(
            data.params.zeroForOne,
            -int256(data.params.amountIn),
            sqrtPriceLimitX96
        );

        IV4PoolManager poolManager = IV4PoolManager(V4_POOL_MANAGER);

        int256 delta = poolManager.swap(poolKey, swapParams, data.params.hookData);
        poolManager.sync(data.params.currencyIn);

        int128 inputDelta = data.params.zeroForOne ? delta.amount0() : delta.amount1();
        require(inputDelta < 0, "V4: Positive input delta");

        amountToPay = uint256(uint128(-inputDelta));
        require(amountToPay == data.params.amountIn, "V4: amountToPay != amountIn");

        int128 outputDelta = data.params.zeroForOne ? delta.amount1() : delta.amount0();
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

    receive() external payable {}
}
