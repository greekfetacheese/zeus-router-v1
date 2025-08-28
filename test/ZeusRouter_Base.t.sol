// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {ZeusRouter} from "../src/ZeusRouter.sol";
import {Commands} from "../src/lib/Commands.sol";
import {Inputs} from "../src/lib/Inputs.sol";
import {IPermit2} from "../src/interfaces/IPermit2.sol";
import {SafeTransferLib} from "../src/lib/SafeTransferLib.sol";
import {Swap} from "../src/lib/Swap.sol";

contract ZeusRouterTest is Test {
    ZeusRouter router;
    address constant ETH = address(0);
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address public constant V4_POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address public constant UNISWAP_V3_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
    address public constant PANCAKE_SWAP_V3_FACTORY = 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865;

    // Tokens
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public constant WBTC = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;

    // Pools
    address public constant V3_WETH_USDC = 0x6c561B446416E1A00E8E93E221854d6eA4171372;
    address public constant V2_WETH_USDC = 0x88A43bbDF9D098eEC7bCEda4e2494615dfD9bB9C;

    // Fees
    uint24 public constant FEE_100 = 100;
    uint24 public constant FEE_500 = 500;
    uint24 public constant FEE_3000 = 3000;
    uint24 public constant FEE_10000 = 10000;

    uint CHAIN_ID = 8453;
    address public user;
    uint256 public userPrivateKey;

    uint256 public ETH_AMOUNT = 10e18;
    uint256 public WETH_AMOUNT = 10e18;
    uint256 public USDC_AMOUNT = 10000e6;

    function setUp() public {
        ZeusRouter.DeployParams memory params = ZeusRouter.DeployParams(
            WETH,
            PERMIT2,
            V4_POOL_MANAGER,
            UNISWAP_V3_FACTORY,
            PANCAKE_SWAP_V3_FACTORY
        );

        router = new ZeusRouter(params);
        (user, userPrivateKey) = makeAddrAndKey("user");
        deal(user, 10 ether);
        deal(WETH, user, WETH_AMOUNT);
        deal(USDC, user, USDC_AMOUNT);
        vm.startPrank(user);
        SafeTransferLib.safeApprove(USDC, PERMIT2, type(uint256).max);
        SafeTransferLib.safeApprove(WETH, PERMIT2, type(uint256).max);
        vm.stopPrank();
    }

    function permitSig(
        uint256 privateKey,
        address token,
        uint256 amount,
        uint256 deadline
    ) internal view returns (bytes memory sig) {
        bytes32 domainSeparator = IPermit2(PERMIT2).DOMAIN_SEPARATOR();

        sig = abi.encode(
            keccak256("PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"),
            token,
            uint160(amount),
            uint48(deadline),
            uint48(0) // nonce
        );
        bytes32 detailsHash = keccak256(sig);

        sig = abi.encode(
            keccak256(
                "PermitSingle(PermitDetails details,address spender,uint256 sigDeadline)PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
            ),
            detailsHash,
            address(router),
            deadline
        );
        bytes32 typedDataHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, keccak256(sig)));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, typedDataHash);
        sig = abi.encodePacked(r, s, v);
    }

    function test_V3_CallbackVerification() public {
        vm.startPrank(user);

        address tokenIn = WETH;
        address tokenOut = WBTC;
        uint256 amountIn = WETH_AMOUNT;
        address payer = user;
        uint24 fee = FEE_500;
        bool permit2 = true;

        bytes memory data = abi.encode(tokenIn, tokenOut, amountIn, payer, fee, permit2);

        vm.expectRevert(bytes("UniswapV3SwapCallback: Msg.sender is not a pool"));
        router.uniswapV3SwapCallback(0, 0, data);

        vm.stopPrank();
    }

    function test_V4_CallbackVerification() public {
        vm.startPrank(user);

        Inputs.V4SwapParams memory swapParams = Inputs.V4SwapParams({
            currencyIn: WETH,
            currencyOut: WBTC,
            amountIn: WETH_AMOUNT,
            amountOutMin: 0,
            fee: FEE_3000,
            tickSpacing: 60,
            zeroForOne: false,
            hooks: address(0),
            hookData: bytes(""),
            recipient: user,
            permit2: true
        });

        Swap.V4CallBackData memory data = Swap.V4CallBackData({payer: user, params: swapParams});

        vm.expectRevert(bytes("UniswapV4SwapCallback: Msg.sender is not PoolManager"));
        router.unlockCallback(abi.encode(data));

        vm.stopPrank();
    }

    function test_V2_should_revert_on_slippage_check() public {
        vm.startPrank(user);

        // PERMIT2 -> V2SWAP
        bytes[] memory inputs = new bytes[](2);
        bytes memory commands = abi.encodePacked(Commands.PERMIT2_PERMIT, Commands.V2_SWAP);

        uint256 deadline = block.timestamp + 1000;

        bytes memory signature = permitSig(userPrivateKey, USDC, USDC_AMOUNT, deadline);
        Inputs.Permit2Permit memory permit2Permit = Inputs.Permit2Permit({
            permitSingle: IPermit2.PermitSingle({
                details: IPermit2.PermitDetails({
                    token: USDC,
                    amount: uint160(USDC_AMOUNT),
                    expiration: uint48(deadline),
                    nonce: 0
                }),
                spender: address(router),
                sigDeadline: deadline
            }),
            signature: signature
        });
        inputs[0] = abi.encode(permit2Permit);

        Inputs.V2V3SwapParams memory swapParams = Inputs.V2V3SwapParams({
            amountIn: USDC_AMOUNT,
            amountOutMin: type(uint256).max,
            tokenIn: USDC,
            tokenOut: WETH,
            pool: V2_WETH_USDC,
            poolVariant: 0,
            recipient: user,
            fee: FEE_3000,
            permit2: true
        });
        inputs[1] = abi.encode(swapParams);

        vm.expectRevert(bytes("SlippageCheck: Insufficient output"));
        router.execute(commands, inputs);

        vm.stopPrank();
    }

    function test_V3_should_revert_on_slippage_check() public {
        vm.startPrank(user);

        // PERMIT2 -> V3SWAP

        bytes[] memory inputs = new bytes[](2);
        bytes memory commands = abi.encodePacked(Commands.PERMIT2_PERMIT, Commands.V3_SWAP);

        uint256 deadline = block.timestamp + 1000;

        bytes memory signature = permitSig(userPrivateKey, USDC, USDC_AMOUNT, deadline);
        Inputs.Permit2Permit memory permit2Permit = Inputs.Permit2Permit({
            permitSingle: IPermit2.PermitSingle({
                details: IPermit2.PermitDetails({
                    token: USDC,
                    amount: uint160(USDC_AMOUNT),
                    expiration: uint48(deadline),
                    nonce: 0
                }),
                spender: address(router),
                sigDeadline: deadline
            }),
            signature: signature
        });

        inputs[0] = abi.encode(permit2Permit);

        Inputs.V2V3SwapParams memory swapParams = Inputs.V2V3SwapParams({
            amountIn: USDC_AMOUNT,
            amountOutMin: type(uint256).max,
            tokenIn: USDC,
            tokenOut: WETH,
            pool: V3_WETH_USDC,
            poolVariant: 1,
            recipient: user,
            fee: FEE_3000,
            permit2: true
        });
        inputs[1] = abi.encode(swapParams);

        vm.expectRevert(bytes("SlippageCheck: Insufficient output"));
        router.execute(commands, inputs);

        vm.stopPrank();
    }

    function test_V4_ETH_Output_should_revert_on_slippage_check() public {
        vm.startPrank(user);

        // PERMIT2 -> V4SWAP

        bytes[] memory inputs = new bytes[](2);
        bytes memory commands = abi.encodePacked(Commands.PERMIT2_PERMIT, Commands.V4_SWAP);

        uint256 deadline = block.timestamp + 1000;

        bytes memory signature = permitSig(userPrivateKey, USDC, USDC_AMOUNT, deadline);
        Inputs.Permit2Permit memory permit2Permit = Inputs.Permit2Permit({
            permitSingle: IPermit2.PermitSingle({
                details: IPermit2.PermitDetails({
                    token: USDC,
                    amount: uint160(USDC_AMOUNT),
                    expiration: uint48(deadline),
                    nonce: 0
                }),
                spender: address(router),
                sigDeadline: deadline
            }),
            signature: signature
        });
        inputs[0] = abi.encode(permit2Permit);

        Inputs.V4SwapParams memory swapParams = Inputs.V4SwapParams({
            currencyIn: USDC,
            currencyOut: ETH,
            amountIn: USDC_AMOUNT,
            amountOutMin: type(uint256).max,
            fee: FEE_3000,
            tickSpacing: 60,
            zeroForOne: false,
            hooks: address(0),
            hookData: bytes(""),
            recipient: user,
            permit2: true
        });
        inputs[1] = abi.encode(swapParams);

        vm.expectRevert(bytes("SlippageCheck: Insufficient output"));
        router.execute(commands, inputs);

        vm.stopPrank();
    }

    function test_V4_ERC_Output_should_revert_on_slippage_check() public {
        vm.startPrank(user);

        bytes[] memory inputs = new bytes[](1);
        bytes memory commands = abi.encodePacked(Commands.V4_SWAP);

        Inputs.V4SwapParams memory swapParams = Inputs.V4SwapParams({
            currencyIn: ETH,
            currencyOut: USDC,
            amountIn: ETH_AMOUNT,
            amountOutMin: type(uint256).max,
            fee: FEE_3000,
            tickSpacing: 60,
            zeroForOne: true,
            hooks: address(0),
            hookData: bytes(""),
            recipient: user,
            permit2: false
        });

        inputs[0] = abi.encode(swapParams);

        vm.expectRevert(bytes("SlippageCheck: Insufficient output"));
        router.execute{value: ETH_AMOUNT}(commands, inputs);

        vm.stopPrank();
    }

    function test_UnwrapWETH_should_revert_on_slippage_check() public {
        vm.startPrank(user);

        bytes[] memory inputs = new bytes[](2);
        bytes memory commands = abi.encodePacked(Commands.PERMIT2_PERMIT, Commands.UNWRAP_WETH);

        uint256 deadline = block.timestamp + 1000;

        bytes memory signature = permitSig(userPrivateKey, WETH, WETH_AMOUNT, deadline);
        Inputs.Permit2Permit memory permit2Permit = Inputs.Permit2Permit({
            permitSingle: IPermit2.PermitSingle({
                details: IPermit2.PermitDetails({
                    token: WETH,
                    amount: uint160(WETH_AMOUNT),
                    expiration: uint48(deadline),
                    nonce: 0
                }),
                spender: address(router),
                sigDeadline: deadline
            }),
            signature: signature
        });

        inputs[0] = abi.encode(permit2Permit);

        Inputs.UnwrapWETH memory unwrapParams = Inputs.UnwrapWETH({recipient: user, amountMin: WETH_AMOUNT + 1});

        inputs[1] = abi.encode(unwrapParams);

        vm.expectRevert(bytes("SlippageCheck: Insufficient WETH"));
        router.execute(commands, inputs);

        vm.stopPrank();
    }

    function test_SWEEP_should_revert_on_slippage_check() public {
        vm.startPrank(user);

        bytes[] memory inputs = new bytes[](2);
        bytes memory commands = abi.encodePacked(Commands.PERMIT2_PERMIT, Commands.SWEEP);

        uint256 deadline = block.timestamp + 1000;

        bytes memory signature = permitSig(userPrivateKey, USDC, USDC_AMOUNT, deadline);
        Inputs.Permit2Permit memory permit2Permit = Inputs.Permit2Permit({
            permitSingle: IPermit2.PermitSingle({
                details: IPermit2.PermitDetails({
                    token: USDC,
                    amount: uint160(USDC_AMOUNT),
                    expiration: uint48(deadline),
                    nonce: 0
                }),
                spender: address(router),
                sigDeadline: deadline
            }),
            signature: signature
        });

        inputs[0] = abi.encode(permit2Permit);

        Inputs.Sweep memory sweepParams = Inputs.Sweep({currency: USDC, recipient: user, amountMin: USDC_AMOUNT + 1});

        inputs[1] = abi.encode(sweepParams);

        vm.expectRevert(bytes("SlippageCheck: Insufficient token balance"));
        router.execute(commands, inputs);

        vm.stopPrank();
    }

    function test_V3_Swap() public {
        vm.startPrank(user);

        bytes[] memory inputs = new bytes[](3);
        bytes memory commands = abi.encodePacked(Commands.PERMIT2_PERMIT, Commands.V3_SWAP, Commands.UNWRAP_WETH);

        uint256 deadline = block.timestamp + 1000;

        bytes memory signature = permitSig(userPrivateKey, USDC, USDC_AMOUNT, deadline);
        Inputs.Permit2Permit memory permit2Permit = Inputs.Permit2Permit({
            permitSingle: IPermit2.PermitSingle({
                details: IPermit2.PermitDetails({
                    token: USDC,
                    amount: uint160(USDC_AMOUNT),
                    expiration: uint48(deadline),
                    nonce: 0
                }),
                spender: address(router),
                sigDeadline: deadline
            }),
            signature: signature
        });

        inputs[0] = abi.encode(permit2Permit);

        Inputs.V2V3SwapParams memory swapParams = Inputs.V2V3SwapParams({
            amountIn: USDC_AMOUNT,
            amountOutMin: 0,
            tokenIn: USDC,
            tokenOut: WETH,
            pool: V3_WETH_USDC,
            poolVariant: 1,
            recipient: address(router),
            fee: FEE_3000,
            permit2: true
        });

        inputs[1] = abi.encode(swapParams);

        Inputs.UnwrapWETH memory unwrapParams = Inputs.UnwrapWETH({recipient: user, amountMin: 0});

        inputs[2] = abi.encode(unwrapParams);

        uint256 balanceBefore = user.balance;
        router.execute(commands, inputs);

        uint256 balanceAfter = user.balance;

        assertGt(balanceAfter, balanceBefore);
        vm.stopPrank();
    }

    function test_V2_Swap() public {
        vm.startPrank(user);

        bytes[] memory inputs = new bytes[](2);
        bytes memory commands = abi.encodePacked(Commands.PERMIT2_PERMIT, Commands.V2_SWAP);

        uint256 deadline = block.timestamp + 1000;

        bytes memory signature = permitSig(userPrivateKey, USDC, USDC_AMOUNT, deadline);
        Inputs.Permit2Permit memory permit2Permit = Inputs.Permit2Permit({
            permitSingle: IPermit2.PermitSingle({
                details: IPermit2.PermitDetails({
                    token: USDC,
                    amount: uint160(USDC_AMOUNT),
                    expiration: uint48(deadline),
                    nonce: 0
                }),
                spender: address(router),
                sigDeadline: deadline
            }),
            signature: signature
        });
        inputs[0] = abi.encode(permit2Permit);

        Inputs.V2V3SwapParams memory swapParams = Inputs.V2V3SwapParams({
            amountIn: USDC_AMOUNT,
            amountOutMin: 0,
            tokenIn: USDC,
            tokenOut: WETH,
            pool: V2_WETH_USDC,
            poolVariant: 0,
            recipient: user,
            fee: FEE_3000,
            permit2: true
        });
        inputs[1] = abi.encode(swapParams);

        uint256 balanceBefore = SafeTransferLib.balanceOf(WETH, user);
        router.execute(commands, inputs);

        uint256 balanceAfter = SafeTransferLib.balanceOf(WETH, user);
        assertGt(balanceAfter, balanceBefore);
        vm.stopPrank();
    }

    function test_Swap_With_ETH_Input() public {
        vm.startPrank(user);

        bytes[] memory inputs = new bytes[](2);
        bytes memory commands = abi.encodePacked(Commands.WRAP_ETH, Commands.V3_SWAP);

        Inputs.WrapETH memory wrapParams = Inputs.WrapETH({recipient: address(router), amount: WETH_AMOUNT});
        inputs[0] = abi.encode(wrapParams);

        Inputs.V2V3SwapParams memory swapParams = Inputs.V2V3SwapParams({
            amountIn: WETH_AMOUNT,
            amountOutMin: 0,
            tokenIn: WETH,
            tokenOut: USDC,
            pool: V3_WETH_USDC,
            poolVariant: 1,
            recipient: user,
            fee: FEE_3000,
            permit2: false
        });

        inputs[1] = abi.encode(swapParams);

        uint256 balanceBefore = SafeTransferLib.balanceOf(USDC, user);
        router.execute{value: WETH_AMOUNT}(commands, inputs);

        uint256 balanceAfter = SafeTransferLib.balanceOf(USDC, user);
        assertGt(balanceAfter, balanceBefore);
        vm.stopPrank();
    }

    function test_Swap_With_ETH_Output() public {
        vm.startPrank(user);

        bytes[] memory inputs = new bytes[](3);
        bytes memory commands = abi.encodePacked(Commands.PERMIT2_PERMIT, Commands.V3_SWAP, Commands.UNWRAP_WETH);

        uint256 deadline = block.timestamp + 1000;

        bytes memory signature = permitSig(userPrivateKey, USDC, USDC_AMOUNT, deadline);
        Inputs.Permit2Permit memory permit2Permit = Inputs.Permit2Permit({
            permitSingle: IPermit2.PermitSingle({
                details: IPermit2.PermitDetails({
                    token: USDC,
                    amount: uint160(USDC_AMOUNT),
                    expiration: uint48(deadline),
                    nonce: 0
                }),
                spender: address(router),
                sigDeadline: deadline
            }),
            signature: signature
        });

        inputs[0] = abi.encode(permit2Permit);

        Inputs.V2V3SwapParams memory swapParams = Inputs.V2V3SwapParams({
            amountIn: USDC_AMOUNT,
            amountOutMin: 0,
            tokenIn: USDC,
            tokenOut: WETH,
            pool: V3_WETH_USDC,
            poolVariant: 1,
            recipient: address(router),
            fee: FEE_3000,
            permit2: true
        });

        inputs[1] = abi.encode(swapParams);

        Inputs.UnwrapWETH memory unwrapParams = Inputs.UnwrapWETH({recipient: user, amountMin: 0});

        inputs[2] = abi.encode(unwrapParams);

        uint256 balanceBefore = user.balance;
        router.execute(commands, inputs);

        uint256 balanceAfter = user.balance;
        assertGt(balanceAfter, balanceBefore);
        vm.stopPrank();
    }
}
