pragma solidity ^0.8.15;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {MockERC20} from "@uniswap/v4-core/test/foundry-tests/utils/MockERC20.sol";
import {IERC20Minimal} from "@uniswap/v4-core/contracts/interfaces/external/IERC20Minimal.sol";

import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import {PoolManager} from "@uniswap/v4-core/contracts/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {PoolModifyPositionTest} from "@uniswap/v4-core/contracts/test/PoolModifyPositionTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/contracts/test/PoolSwapTest.sol";
import {PoolDonateTest} from "@uniswap/v4-core/contracts/test/PoolDonateTest.sol";
import {Deployers} from "@uniswap/v4-core/test/foundry-tests/utils/Deployers.sol";
import {TokenFixture} from "@uniswap/v4-core/test/foundry-tests/utils/TokenFixture.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {TWAMMSmartHook} from "../contracts/hooks/examples/TWAMMSmartHook.sol";
import {ITWAMM} from "../contracts/interfaces/ITWAMM.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";

import {TWAMMSmartHookImpl} from "./shared/implementation/TWAMMSmartHookImpl.sol";
import {EntryPoint, IExternalHook} from "../contracts/smarthook/EntryPoint.sol";

contract TWAMMSmartHookTest is Test, Deployers, TokenFixture, GasSnapshot {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    event SubmitOrder(
        PoolId indexed poolId,
        address indexed owner,
        uint160 expiration,
        bool zeroForOne,
        uint256 sellRate,
        uint256 earningsFactorLast
    );

    event UpdateOrder(
        PoolId indexed poolId,
        address indexed owner,
        uint160 expiration,
        bool zeroForOne,
        uint256 sellRate,
        uint256 earningsFactorLast
    );

    // address constant TWAMMAddr = address(uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_MODIFY_POSITION_FLAG));
    TWAMMSmartHook twamm = TWAMMSmartHook(
        address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_MODIFY_POSITION_FLAG))
    );
    // TWAMM twamm;
    PoolManager manager;
    PoolModifyPositionTest modifyPositionRouter;
    PoolSwapTest swapRouter;
    PoolDonateTest donateRouter;
    address hookAddress;
    MockERC20 token0;
    MockERC20 token1;
    PoolKey poolKey;
    PoolId poolId;

    //external caller part
    EntryPoint entryPoint;
    IExternalHook.Trigger[] triggers;

    function setUp() public {
        initializeTokens();
        token0 = MockERC20(Currency.unwrap(currency0));
        token1 = MockERC20(Currency.unwrap(currency1));

        manager = new PoolManager(500000);

        entryPoint = new EntryPoint();
        triggers.push(IExternalHook.Trigger.TIME_INTERVAL_1000S);

        TWAMMSmartHookImpl impl = new TWAMMSmartHookImpl(manager, 10_000, entryPoint, triggers, twamm);
        (, bytes32[] memory writes) = vm.accesses(address(impl));
        vm.etch(address(twamm), address(impl).code);
        // for each storage key that was written during the hook implementation, copy the value over
        unchecked {
            for (uint256 i = 0; i < writes.length; i++) {
                bytes32 slot = writes[i];
                vm.store(address(twamm), slot, vm.load(address(impl), slot));
            }
        }

        modifyPositionRouter = new PoolModifyPositionTest(IPoolManager(address(manager)));
        swapRouter = new PoolSwapTest(IPoolManager(address(manager)));

        poolKey = PoolKey(Currency.wrap(address(token0)), Currency.wrap(address(token1)), 3000, 60, twamm);
        poolId = poolKey.toId();

        manager.initialize(poolKey, SQRT_RATIO_1_1, ZERO_BYTES);

        token0.approve(address(modifyPositionRouter), 100 ether);
        token1.approve(address(modifyPositionRouter), 100 ether);
        token0.mint(address(this), 100 ether);
        token1.mint(address(this), 100 ether);
        modifyPositionRouter.modifyPosition(poolKey, IPoolManager.ModifyPositionParams(-60, 60, 10 ether), ZERO_BYTES);
        modifyPositionRouter.modifyPosition(poolKey, IPoolManager.ModifyPositionParams(-120, 120, 10 ether), ZERO_BYTES);
        modifyPositionRouter.modifyPosition(
            poolKey,
            IPoolManager.ModifyPositionParams(TickMath.minUsableTick(60), TickMath.maxUsableTick(60), 10 ether),
            ZERO_BYTES
        );
    }

    function printPoolKey(PoolKey memory pkey) internal view {
        console2.log("currency0:", Currency.unwrap(pkey.currency0));
        console2.log("currency1:", Currency.unwrap(pkey.currency1));
        console2.log("fee:", pkey.fee);
        console2.log("tickSpacing:", pkey.tickSpacing);
        console2.log("hooks:", address(pkey.hooks));
    }

    function testTWAMMSmartHook_FromExternalTrigger() public {
        //address eoa = address(this);
        IExternalHook.Trigger trigger = IExternalHook.Trigger.TIME_INTERVAL_1000S;
        entryPoint.handleOps(trigger);
        printPoolKey(twamm.getPoolKey(0));
    }

    function externalUserTriggerTWAMM() public {
        IExternalHook.Trigger trigger = IExternalHook.Trigger.TIME_INTERVAL_1000S;
        entryPoint.handleOps(trigger);
        //twamm.executeOps(trigger);
    }

    function submitOrdersBothDirections()
        internal
        returns (ITWAMM.OrderKey memory key1, ITWAMM.OrderKey memory key2, uint256 amount)
    {
        key1 = ITWAMM.OrderKey(address(this), 30000, true);
        key2 = ITWAMM.OrderKey(address(this), 30000, false);
        amount = 1 ether;

        token0.approve(address(twamm), amount);
        token1.approve(address(twamm), amount);

        vm.warp(10000);
        twamm.submitOrder(poolKey, key1, amount);
        twamm.submitOrder(poolKey, key2, amount);
    }

    function submitOrderSingleDirection(bool zeroForOne, uint256 amount, uint256 endingtime)
        internal
        returns (ITWAMM.OrderKey memory key)
    {
        key = ITWAMM.OrderKey(address(this), uint160(endingtime), zeroForOne);

        token0.approve(address(twamm), amount);
        token1.approve(address(twamm), amount);

        twamm.submitOrder(poolKey, key, amount);
    }

    function otherUserSwapTriggerTWAMMorder(uint256 amount) internal {
        PoolSwapTest.TestSettings memory testSwapSet =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});
        (uint160 sqrtPriceX96,,,) = manager.getSlot0(poolId);
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams(false, int256(amount), sqrtPriceX96 * 115 / 100);

        token1.approve(address(swapRouter), amount);
        swapRouter.swap(poolKey, params, testSwapSet, ZERO_BYTES);
    }

    function testTWAMMSmartHook_OrderFill_SingleSide_OneForZero_Crosstick() public {
        bool zeroForOne = false;
        uint256 twammAmount = 1 ether;
        uint256 endingTime = 30_000;

        uint256 lasttimestep = 10000;
        vm.warp(lasttimestep);
        submitOrderSingleDirection(zeroForOne, twammAmount, endingTime);

        uint256 balanceTWAMMBefore = token1.balanceOf(address(twamm));
        uint256 orderDuration = endingTime - lasttimestep;
        (uint256 sellRateCurrent,) = twamm.getOrderPool(poolKey, zeroForOne);

        assertEq(balanceTWAMMBefore, twammAmount);
        assertEq(sellRateCurrent, twammAmount / orderDuration);

        // set timestamp to halfway through the order
        lasttimestep = 30000;
        vm.warp(lasttimestep);

        //twamm.executeTWAMMOrders(poolKey);
        otherUserSwapTriggerTWAMMorder(0.001 ether);
        //externalUserTriggerTWAMM();

        uint256 balanceTWAMMAfter = token1.balanceOf(address(twamm));
        assertEq(
            balanceTWAMMAfter, lasttimestep > endingTime ? 0 : twammAmount * (endingTime - lasttimestep) / orderDuration
        );
    }

    function testTWAMMSmartHook_OrderFill_SingleSide_ZeroForOne_Crosstick() public {
        bool zeroForOne = true;
        uint256 twammAmount = 1 ether;
        uint256 endingTime = 30_000;

        uint256 lasttimestep = 10000;
        vm.warp(lasttimestep);
        submitOrderSingleDirection(zeroForOne, twammAmount, endingTime);

        uint256 orderDuration = endingTime - lasttimestep;
        (uint256 sellRateCurrent,) = twamm.getOrderPool(poolKey, zeroForOne);

        assertEq(token0.balanceOf(address(twamm)), twammAmount);
        assertEq(sellRateCurrent, twammAmount / orderDuration);

        // set timestamp to halfway through the order
        lasttimestep = 20000;
        vm.warp(lasttimestep);

        //twamm.executeTWAMMOrders(poolKey);
        //otherUserSwapTriggerTWAMMorder(0.001 ether);
        externalUserTriggerTWAMM();

        uint256 balanceTWAMMAfter = token0.balanceOf(address(twamm));
        assertEq(
            balanceTWAMMAfter, lasttimestep > endingTime ? 0 : twammAmount * (endingTime - lasttimestep) / orderDuration
        );
    }

    function testTWAMMSmartHook_OrderFill_SingleSide_ZeroForOne_NoCross() public {
        bool zeroForOne = true;
        uint256 twammAmount = 0.001 ether;
        uint256 endingTime = 20_000;
        uint256 startingTime = 10_000;
        uint256 lasttimestep = startingTime;
        vm.warp(lasttimestep);
        submitOrderSingleDirection(zeroForOne, twammAmount, endingTime);

        uint256 orderDuration = endingTime - startingTime;
        (uint256 sellRateCurrent,) = twamm.getOrderPool(poolKey, zeroForOne); //uint256 earningsFactorCurrent
        assertEq(token0.balanceOf(address(twamm)), twammAmount);
        assertEq(sellRateCurrent, twammAmount / orderDuration);

        // set timestamp to halfway through the order
        lasttimestep = 30000;
        vm.warp(lasttimestep);

        //otherUserSwapTriggerTWAMMorder(0.001 ether);
        externalUserTriggerTWAMM();

        uint256 balance0TWAMMAfter = token0.balanceOf(address(twamm));
        assertEq(
            balance0TWAMMAfter,
            lasttimestep > endingTime ? 0 : (endingTime - lasttimestep) * twammAmount / orderDuration
        );
    }
}
