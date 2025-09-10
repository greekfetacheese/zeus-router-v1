// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ZeusSwapDelegator} from "../src/ZeusDelegate.sol";
import {SafeTransferLib} from "../src/lib/SafeTransferLib.sol";

contract ZeusDelegateTest is Test {
    ZeusSwapDelegator ZeusDelegator;
    address constant ETH = address(0);

    bytes1 constant V2_SWAP = 0x01;
    bytes1 constant V3_SWAP = 0x02;
    bytes1 constant V4_SWAP = 0x03;
    bytes1 constant WRAP_ETH = 0x04;
    bytes1 constant UNWRAP_WETH = 0x05;
    bytes1 constant WRAP_ETH_NO_CHECK = 0x06;

    address public constant V4_POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address public constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public constant PANCAKE_SWAP_V3_FACTORY = 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865;

    // Tokens
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;

    // Pools
    address public constant UNI_V2_USDC_DAI = 0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5;
    address public constant UNI_V3_USDC_WETH = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address public constant PANKCAKE_V3_WETH_USDT = 0x6CA298D2983aB03Aa1dA7679389D955A4eFEE15C;

    // Fees
    uint24 public constant FEE_100 = 100;
    uint24 public constant FEE_500 = 500;
    uint24 public constant FEE_3000 = 3000;
    uint24 public constant FEE_10000 = 10000;

    uint CHAIN_ID = 1;
    address payable public Alice;
    uint256 public AliceKey;

    address Bob;
    uint256 BobKey;

    uint256 public ETH_AMOUNT = 10e18;
    uint256 public WETH_AMOUNT = 10e18;
    uint256 public USDC_AMOUNT = 10000e6;
    uint256 public DAI_AMOUNT = 10000e18;
    uint256 public USDT_AMOUNT = 10000e6;
    uint256 public UNI_AMOUNT = 10000e18;

    function setUp() public {
        ZeusSwapDelegator.DeployParams memory params = ZeusSwapDelegator.DeployParams(
            WETH,
            V4_POOL_MANAGER,
            UNISWAP_V3_FACTORY,
            PANCAKE_SWAP_V3_FACTORY
        );

        ZeusDelegator = new ZeusSwapDelegator(params);
        (address aliceAddr, uint256 aliceKey) = makeAddrAndKey("Alice");
        Alice = payable(aliceAddr);
        AliceKey = aliceKey;

        (address bobAddr, uint256 bobKey) = makeAddrAndKey("Bob");
        Bob = bobAddr;
        BobKey = bobKey;

        deal(Alice, 10 ether);
        deal(WETH, Alice, WETH_AMOUNT);
        deal(USDC, Alice, USDC_AMOUNT);
        deal(DAI, Alice, DAI_AMOUNT);
        deal(USDT, Alice, USDT_AMOUNT);
        deal(UNI, Alice, UNI_AMOUNT);
    }

    function test_V3_CallbackVerification() public {
        vm.startPrank(Alice);

        address tokenIn = WETH;
        address tokenOut = USDT;
        uint256 amountIn = WETH_AMOUNT;
        uint24 fee = FEE_500;

        bytes memory data = abi.encode(tokenIn, tokenOut, amountIn, fee);

        vm.expectRevert(bytes("UniswapV3SwapCallback: Msg.sender is not a pool"));
        ZeusDelegator.uniswapV3SwapCallback(0, 0, data);

        vm.stopPrank();
    }

    function test_V4_CallbackVerification() public {
        vm.startPrank(Alice);

        ZeusSwapDelegator.V4SwapArgs memory data = ZeusSwapDelegator.V4SwapArgs({
            currencyIn: USDT,
            currencyOut: WETH,
            amountIn: USDT_AMOUNT,
            fee: FEE_3000,
            tickSpacing: 60,
            zeroForOne: false,
            hooks: address(0),
            hookData: bytes(""),
            recipient: Alice
        });

        vm.expectRevert(bytes("UniswapV4SwapCallback: Msg.sender is not PoolManager"));
        ZeusDelegator.unlockCallback(abi.encode(data));

        vm.stopPrank();
    }

    function test_WrapETH_SlippageCheck() public {
        vm.startPrank(Alice);

        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(ZeusDelegator), AliceKey);

        vm.attachDelegation(signedDelegation);

        bytes[] memory inputs = new bytes[](1);
        bytes memory commands = abi.encodePacked(WRAP_ETH);

        ZeusSwapDelegator.WrapETH memory wrapParams = ZeusSwapDelegator.WrapETH({amountMin: ETH_AMOUNT});

        inputs[0] = abi.encode(wrapParams);

        ZeusSwapDelegator.ZParams memory params = ZeusSwapDelegator.ZParams({
            commands: commands,
            inputs: inputs,
            currencyOut: WETH,
            amountMin: type(uint256).max
        });

        vm.expectRevert(bytes("SlippageCheck: Insufficient ETH"));
        ZeusSwapDelegator(Alice).zSwap(params);

        vm.stopPrank();
    }

    function test_UnwrapWETH_SlippageCheck() public {
        vm.startPrank(Alice);

        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(ZeusDelegator), AliceKey);

        vm.attachDelegation(signedDelegation);

        bytes[] memory inputs = new bytes[](1);
        bytes memory commands = abi.encodePacked(UNWRAP_WETH);

        ZeusSwapDelegator.UnwrapWETH memory unwrapParams = ZeusSwapDelegator.UnwrapWETH({amountMin: WETH_AMOUNT});

        inputs[0] = abi.encode(unwrapParams);

        ZeusSwapDelegator.ZParams memory params = ZeusSwapDelegator.ZParams({
            commands: commands,
            inputs: inputs,
            currencyOut: WETH,
            amountMin: type(uint256).max
        });

        vm.expectRevert(bytes("SlippageCheck: Insufficient WETH"));
        ZeusSwapDelegator(Alice).zSwap(params);

        vm.stopPrank();
    }

    function test_swap_SlippageCheck() public {
        vm.startPrank(Alice);

        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(ZeusDelegator), AliceKey);

        vm.attachDelegation(signedDelegation);

        bytes memory code = Alice.code;
        require(code.length > 0, "no code written to Alice");

        bytes[] memory inputs = new bytes[](1);
        bytes memory commands = abi.encodePacked(V2_SWAP);

        ZeusSwapDelegator.V2V3SwapParams memory swapParams = ZeusSwapDelegator.V2V3SwapParams({
            amountIn: USDC_AMOUNT,
            tokenIn: USDC,
            tokenOut: DAI,
            pool: UNI_V2_USDC_DAI,
            poolVariant: 0x00,
            fee: FEE_3000
        });

        inputs[0] = abi.encode(swapParams);

        ZeusSwapDelegator.ZParams memory params = ZeusSwapDelegator.ZParams({
            commands: commands,
            inputs: inputs,
            currencyOut: DAI,
            amountMin: type(uint256).max
        });

        vm.expectRevert(bytes("SlippageCheck: Insufficient output"));
        ZeusSwapDelegator(Alice).zSwap(params);

        vm.stopPrank();
    }

    function test_V2Swap() public {
        vm.startPrank(Alice);

        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(ZeusDelegator), AliceKey);

        vm.attachDelegation(signedDelegation);

        bytes[] memory inputs = new bytes[](1);
        bytes memory commands = abi.encodePacked(V2_SWAP);

        ZeusSwapDelegator.V2V3SwapParams memory swapParams = ZeusSwapDelegator.V2V3SwapParams({
            amountIn: USDC_AMOUNT,
            tokenIn: USDC,
            tokenOut: DAI,
            pool: UNI_V2_USDC_DAI,
            poolVariant: 0x00,
            fee: FEE_3000
        });

        inputs[0] = abi.encode(swapParams);

        ZeusSwapDelegator.ZParams memory params = ZeusSwapDelegator.ZParams({
            commands: commands,
            inputs: inputs,
            currencyOut: DAI,
            amountMin: 0
        });

        uint256 balanceBefore = SafeTransferLib.balanceOf(DAI, Alice);
        ZeusSwapDelegator(Alice).zSwap(params);

        uint256 balanceAfter = SafeTransferLib.balanceOf(DAI, Alice);
        assertGt(balanceAfter, balanceBefore);
        vm.stopPrank();
    }

    function test_V3Swap() public {
        vm.startPrank(Alice);

        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(ZeusDelegator), AliceKey);

        vm.attachDelegation(signedDelegation);

        bytes[] memory inputs = new bytes[](1);
        bytes memory commands = abi.encodePacked(V3_SWAP);

        ZeusSwapDelegator.V2V3SwapParams memory swapParams = ZeusSwapDelegator.V2V3SwapParams({
            amountIn: WETH_AMOUNT,
            tokenIn: WETH,
            tokenOut: USDC,
            pool: UNI_V3_USDC_WETH,
            poolVariant: 0x01,
            fee: FEE_500
        });

        inputs[0] = abi.encode(swapParams);

        ZeusSwapDelegator.ZParams memory params = ZeusSwapDelegator.ZParams({
            commands: commands,
            inputs: inputs,
            currencyOut: USDC,
            amountMin: 0
        });

        uint256 balanceBefore = SafeTransferLib.balanceOf(USDC, Alice);
        ZeusSwapDelegator(Alice).zSwap(params);

        uint256 balanceAfter = SafeTransferLib.balanceOf(USDC, Alice);
        assertGt(balanceAfter, balanceBefore);
        vm.stopPrank();
    }

    function test_V4Swap() public {
        vm.startPrank(Alice);

        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(ZeusDelegator), AliceKey);

        vm.attachDelegation(signedDelegation);

        bytes[] memory inputs = new bytes[](1);
        bytes memory commands = abi.encodePacked(V4_SWAP);

        ZeusSwapDelegator.V4SwapArgs memory swapParams = ZeusSwapDelegator.V4SwapArgs({
            currencyIn: USDT,
            currencyOut: WBTC,
            amountIn: USDT_AMOUNT,
            fee: FEE_3000,
            tickSpacing: 60,
            zeroForOne: false,
            hooks: address(0),
            hookData: bytes(""),
            recipient: Alice
        });

        inputs[0] = abi.encode(swapParams);

        ZeusSwapDelegator.ZParams memory params = ZeusSwapDelegator.ZParams({
            commands: commands,
            inputs: inputs,
            currencyOut: WBTC,
            amountMin: 0
        });

        uint256 balanceBefore = SafeTransferLib.balanceOf(WBTC, Alice);
        ZeusSwapDelegator(Alice).zSwap(params);

        uint256 balanceAfter = SafeTransferLib.balanceOf(WBTC, Alice);
        assertGt(balanceAfter, balanceBefore);
        vm.stopPrank();
    }
}
