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
    address public user;
    uint256 public userPrivateKey;

    uint256 public ETH_AMOUNT = 10e18;
    uint256 public WETH_AMOUNT = 10e18;
    uint256 public USDC_AMOUNT = 10000e6;
    uint256 public DAI_AMOUNT = 10000e18;
    uint256 public USDT_AMOUNT = 10000e6;
    uint256 public UNI_AMOUNT = 10000e18;

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
        deal(DAI, user, DAI_AMOUNT);
        deal(USDT, user, USDT_AMOUNT);
        deal(UNI, user, UNI_AMOUNT);
        vm.startPrank(user);
        SafeTransferLib.safeApprove(USDC, PERMIT2, type(uint256).max);
        SafeTransferLib.safeApprove(DAI, PERMIT2, type(uint256).max);
        SafeTransferLib.safeApprove(WETH, PERMIT2, type(uint256).max);
        SafeTransferLib.safeApprove(UNI, PERMIT2, type(uint256).max);
        SafeTransferLib.safeApprove(USDT, PERMIT2, type(uint256).max);
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

    function testDeadline() public {
        vm.startPrank(user);

        bytes[] memory inputs = new bytes[](2);
        bytes memory commands = abi.encodePacked(Commands.PERMIT2_PERMIT, Commands.V2_SWAP);

        uint256 deadline = block.timestamp - 1;

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
            tokenIn: USDC,
            tokenOut: DAI,
            pool: UNI_V2_USDC_DAI,
            poolVariant: 0,
            recipient: user,
            fee: FEE_3000,
            permit2: true
        });

        inputs[1] = abi.encode(swapParams);

        vm.expectRevert(bytes("Deadline: Expired"));

        Inputs.ZParams memory params = Inputs.ZParams({
            commands: commands,
            inputs: inputs,
            currencyOut: DAI,
            amountMin: 0,
            deadline: deadline
        });

        router.zSwap(params);

        vm.stopPrank();
    }

    function test_V3_CallbackVerification() public {
        vm.startPrank(user);

        address tokenIn = WETH;
        address tokenOut = USDT;
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
            currencyIn: USDT,
            currencyOut: WBTC,
            amountIn: USDT_AMOUNT,
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
            tokenIn: USDC,
            tokenOut: DAI,
            pool: UNI_V2_USDC_DAI,
            poolVariant: 0,
            recipient: user,
            fee: FEE_3000,
            permit2: true
        });
        inputs[1] = abi.encode(swapParams);

        vm.expectRevert(bytes("SlippageCheck: Insufficient output"));

        Inputs.ZParams memory params = Inputs.ZParams({
            commands: commands,
            inputs: inputs,
            currencyOut: DAI,
            amountMin: type(uint256).max,
            deadline: deadline
        });

        router.zSwap(params);

        vm.stopPrank();
    }

    function test_V4_ETH_Output_should_revert_on_slippage_check() public {
        vm.startPrank(user);

        // PERMIT2 -> V4SWAP

        bytes[] memory inputs = new bytes[](2);
        bytes memory commands = abi.encodePacked(Commands.PERMIT2_PERMIT, Commands.V4_SWAP);

        uint256 deadline = block.timestamp + 1000;

        bytes memory signature = permitSig(userPrivateKey, UNI, UNI_AMOUNT, deadline);
        Inputs.Permit2Permit memory permit2Permit = Inputs.Permit2Permit({
            permitSingle: IPermit2.PermitSingle({
                details: IPermit2.PermitDetails({
                    token: UNI,
                    amount: uint160(UNI_AMOUNT),
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
            currencyIn: UNI,
            currencyOut: ETH,
            amountIn: UNI_AMOUNT,
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

        Inputs.ZParams memory params = Inputs.ZParams({
            commands: commands,
            inputs: inputs,
            currencyOut: ETH,
            amountMin: type(uint256).max,
            deadline: deadline
        });

        router.zSwap(params);

        vm.stopPrank();
    }

    function test_Swap_With_WETH_Output() public {
        vm.startPrank(user);

        bytes[] memory inputs = new bytes[](5);
        bytes memory commands = abi.encodePacked(
            Commands.PERMIT2_PERMIT,
            Commands.V4_SWAP,
            Commands.PERMIT2_PERMIT,
            Commands.V3_SWAP,
            Commands.WRAP_ALL_ETH
        );

        uint256 deadline = block.timestamp + 1000;

        bytes memory signature = permitSig(userPrivateKey, UNI, UNI_AMOUNT, deadline);
        Inputs.Permit2Permit memory permit2Permit = Inputs.Permit2Permit({
            permitSingle: IPermit2.PermitSingle({
                details: IPermit2.PermitDetails({
                    token: UNI,
                    amount: uint160(UNI_AMOUNT),
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
            currencyIn: UNI,
            currencyOut: ETH,
            amountIn: UNI_AMOUNT,
            fee: FEE_3000,
            tickSpacing: 60,
            zeroForOne: false,
            hooks: address(0),
            hookData: bytes(""),
            recipient: address(router),
            permit2: true
        });

        inputs[1] = abi.encode(swapParams);

        bytes memory signature2 = permitSig(userPrivateKey, USDC, USDC_AMOUNT, deadline);
        Inputs.Permit2Permit memory permit2Permit2 = Inputs.Permit2Permit({
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
            signature: signature2
        });

        inputs[2] = abi.encode(permit2Permit2);

        Inputs.V2V3SwapParams memory swapParams2 = Inputs.V2V3SwapParams({
            amountIn: USDC_AMOUNT,
            tokenIn: USDC,
            tokenOut: WETH,
            pool: UNI_V3_USDC_WETH,
            poolVariant: 1,
            recipient: address(router),
            fee: FEE_500,
            permit2: true
        });

        inputs[3] = abi.encode(swapParams2);

        Inputs.WrapAllETH memory wrapAllEthParams = Inputs.WrapAllETH({recipient: user});

        inputs[4] = abi.encode(wrapAllEthParams);

        Inputs.ZParams memory params = Inputs.ZParams({
            commands: commands,
            inputs: inputs,
            currencyOut: WETH,
            amountMin: 0,
            deadline: deadline
        });

        uint256 balanceBefore = SafeTransferLib.balanceOf(WETH, user);

        router.zSwap(params);

        uint256 balanceAfter = SafeTransferLib.balanceOf(WETH, user);
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
            tokenIn: USDC,
            tokenOut: DAI,
            pool: UNI_V2_USDC_DAI,
            poolVariant: 0,
            recipient: user,
            fee: FEE_3000,
            permit2: true
        });
        inputs[1] = abi.encode(swapParams);

        uint256 balanceBefore = SafeTransferLib.balanceOf(DAI, user);

        Inputs.ZParams memory params = Inputs.ZParams({
            commands: commands,
            inputs: inputs,
            currencyOut: DAI,
            amountMin: 0,
            deadline: deadline
        });

        router.zSwap(params);

        uint256 balanceAfter = SafeTransferLib.balanceOf(DAI, user);
        assertGt(balanceAfter, balanceBefore);
        vm.stopPrank();
    }

    function test_PancakeV3() public {
        vm.startPrank(user);

        bytes[] memory inputs = new bytes[](2);
        bytes memory commands = abi.encodePacked(Commands.PERMIT2_PERMIT, Commands.V3_SWAP);

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

        Inputs.V2V3SwapParams memory swapParams = Inputs.V2V3SwapParams({
            amountIn: WETH_AMOUNT,
            tokenIn: WETH,
            tokenOut: USDT,
            pool: PANKCAKE_V3_WETH_USDT,
            poolVariant: 1,
            recipient: user,
            fee: FEE_500,
            permit2: true
        });

        inputs[1] = abi.encode(swapParams);

        uint256 balanceBefore = SafeTransferLib.balanceOf(USDT, user);

        Inputs.ZParams memory params = Inputs.ZParams({
            commands: commands,
            inputs: inputs,
            currencyOut: USDT,
            amountMin: 0,
            deadline: deadline
        });

        router.zSwap(params);

        uint256 balanceAfter = SafeTransferLib.balanceOf(USDT, user);
        assertGt(balanceAfter, balanceBefore);
        vm.stopPrank();
    }

    function test_V3_Swap() public {
        vm.startPrank(user);

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
            tokenIn: USDC,
            tokenOut: WETH,
            pool: UNI_V3_USDC_WETH,
            poolVariant: 1,
            recipient: user,
            fee: FEE_500,
            permit2: true
        });

        inputs[1] = abi.encode(swapParams);

        uint256 balanceBefore = SafeTransferLib.balanceOf(WETH, user);

        Inputs.ZParams memory params = Inputs.ZParams({
            commands: commands,
            inputs: inputs,
            currencyOut: WETH,
            amountMin: 0,
            deadline: deadline
        });

        router.zSwap(params);

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
            tokenIn: WETH,
            tokenOut: USDC,
            pool: UNI_V3_USDC_WETH,
            poolVariant: 1,
            recipient: user,
            fee: FEE_500,
            permit2: false
        });

        inputs[1] = abi.encode(swapParams);

        Inputs.ZParams memory params = Inputs.ZParams({
            commands: commands,
            inputs: inputs,
            currencyOut: USDC,
            amountMin: 0,
            deadline: block.timestamp + 1000
        });

        uint256 balanceBefore = SafeTransferLib.balanceOf(USDC, user);
        router.zSwap{value: WETH_AMOUNT}(params);

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
            tokenIn: USDC,
            tokenOut: WETH,
            pool: UNI_V3_USDC_WETH,
            poolVariant: 1,
            recipient: address(router),
            fee: FEE_500,
            permit2: true
        });

        inputs[1] = abi.encode(swapParams);

        Inputs.UnwrapWETH memory unwrapParams = Inputs.UnwrapWETH({recipient: user});

        inputs[2] = abi.encode(unwrapParams);

        Inputs.ZParams memory params = Inputs.ZParams({
            commands: commands,
            inputs: inputs,
            currencyOut: ETH,
            amountMin: 0,
            deadline: deadline
        });

        uint256 balanceBefore = user.balance;
        router.zSwap(params);

        uint256 balanceAfter = user.balance;
        assertGt(balanceAfter, balanceBefore);
        vm.stopPrank();
    }

    function test_V4_Swap() public {
        vm.startPrank(user);

        bytes[] memory inputs = new bytes[](2);
        bytes memory commands = abi.encodePacked(Commands.PERMIT2_PERMIT, Commands.V4_SWAP);

        uint256 deadline = block.timestamp + 1000;

        bytes memory signature = permitSig(userPrivateKey, USDT, USDT_AMOUNT, deadline);
        Inputs.Permit2Permit memory permit2Permit = Inputs.Permit2Permit({
            permitSingle: IPermit2.PermitSingle({
                details: IPermit2.PermitDetails({
                    token: USDT,
                    amount: uint160(USDT_AMOUNT),
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
            currencyIn: USDT,
            currencyOut: WBTC,
            amountIn: USDT_AMOUNT,
            fee: FEE_3000,
            tickSpacing: 60,
            zeroForOne: false,
            hooks: address(0),
            hookData: bytes(""),
            recipient: user,
            permit2: true
        });
        inputs[1] = abi.encode(swapParams);

        uint256 balanceBefore = SafeTransferLib.balanceOf(WBTC, user);

        Inputs.ZParams memory params = Inputs.ZParams({
            commands: commands,
            inputs: inputs,
            currencyOut: WBTC,
            amountMin: 0,
            deadline: deadline
        });

        router.zSwap(params);

        uint256 balanceAfter = SafeTransferLib.balanceOf(WBTC, user);
        assertGt(balanceAfter, balanceBefore);
        vm.stopPrank();
    }

    function test_V4_ETH_Input_ERC20_Output() public {
        vm.startPrank(user);

        bytes[] memory inputs = new bytes[](1);
        bytes memory commands = abi.encodePacked(Commands.V4_SWAP);

        Inputs.V4SwapParams memory swapParams = Inputs.V4SwapParams({
            currencyIn: ETH,
            currencyOut: UNI,
            amountIn: ETH_AMOUNT,
            fee: FEE_3000,
            tickSpacing: 60,
            zeroForOne: true,
            hooks: address(0),
            hookData: bytes(""),
            recipient: user,
            permit2: false
        });
        inputs[0] = abi.encode(swapParams);

        uint256 balanceBefore = SafeTransferLib.balanceOf(UNI, user);

        Inputs.ZParams memory params = Inputs.ZParams({
            commands: commands,
            inputs: inputs,
            currencyOut: UNI,
            amountMin: 0,
            deadline: block.timestamp + 1000
        });

        router.zSwap{value: ETH_AMOUNT}(params);

        uint256 balanceAfter = SafeTransferLib.balanceOf(UNI, user);
        assertGt(balanceAfter, balanceBefore);
        vm.stopPrank();
    }

    function test_V4_ERC20_Input_ETH_Output() public {
        vm.startPrank(user);

        bytes[] memory inputs = new bytes[](2);
        bytes memory commands = abi.encodePacked(Commands.PERMIT2_PERMIT, Commands.V4_SWAP);

        uint256 deadline = block.timestamp + 1000;

        bytes memory signature = permitSig(userPrivateKey, UNI, UNI_AMOUNT, deadline);
        Inputs.Permit2Permit memory permit2Permit = Inputs.Permit2Permit({
            permitSingle: IPermit2.PermitSingle({
                details: IPermit2.PermitDetails({
                    token: UNI,
                    amount: uint160(UNI_AMOUNT),
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
            currencyIn: UNI,
            currencyOut: ETH,
            amountIn: UNI_AMOUNT,
            fee: FEE_3000,
            tickSpacing: 60,
            zeroForOne: false,
            hooks: address(0),
            hookData: bytes(""),
            recipient: user,
            permit2: true
        });
        inputs[1] = abi.encode(swapParams);

        uint256 balanceBefore = user.balance;

        Inputs.ZParams memory params = Inputs.ZParams({
            commands: commands,
            inputs: inputs,
            currencyOut: ETH,
            amountMin: 0,
            deadline: deadline
        });

        router.zSwap(params);

        uint256 balanceAfter = user.balance;
        assertGt(balanceAfter, balanceBefore);
        vm.stopPrank();
    }
}
