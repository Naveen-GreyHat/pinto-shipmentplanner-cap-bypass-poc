// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ShipmentPlanner.sol";

contract ShipmentPlannerBugTest is Test {
    ShipmentPlanner planner;
    MockBeanstalk beanstalk;
    MockBean bean;
    MockPayback payback;

    uint256 constant FIELD_ID = 1;

    function setUp() public {
        beanstalk = new MockBeanstalk();

        // Bean supply aisa choose kiya hai ke budgetMintRatio() = 0
        // => paybackRatio = PRECISION (1e18), require(paybackRatio > 0) pass
        uint256 seasonalMints = 100_000e6;
        uint256 supply = 1_000_000_000e6 + seasonalMints * 2; // > SUPPLY_BUDGET_FLIP + seasonalMints
        bean = new MockBean(supply);

        planner = new ShipmentPlanner(address(beanstalk), address(bean));
        payback = new MockPayback();

        // Large unharvestable pods
        beanstalk.setTotalUnharvest(FIELD_ID, 1_000_000e6); // 1,000,000
        beanstalk.setSeasonMint(seasonalMints);             // minted beans
        beanstalk.setHarvesting(true);

        // Dono remaining > 0 => 1% branch
        payback.setRemaining(10_000e6, 20_000e6);
    }

    function test_CapBypassBug() public {
        bytes memory data = abi.encode(FIELD_ID, address(payback));

        ShipmentPlan memory plan = planner.getPaybackFieldPlan(data);

        Season memory s = beanstalk.time();
        uint256 minted = s.standardMintedBeans;

        uint256 expectedCap = (minted * 1) / 100; // 1% of minted beans
        uint256 totalUnharvest = beanstalk.totalUnharvestable(FIELD_ID);

        console.log("totalUnharvest      =", totalUnharvest);
        console.log("expectedCap (1%)   =", expectedCap);
        console.log("returned cap       =", plan.cap);

        // sanity: unharvest > expected cap
        assertGt(totalUnharvest, expectedCap, "setup: totalUnharvest should be > cap");

        // ✅ Yeh do asserts bug ko clearly dikhate hain:
        // 1) contract ne cap ko totalUnharvest ke equal rakha
        assertEq(plan.cap, totalUnharvest, "bug: cap equals totalUnharvestable (no limit applied)");

        // 2) cap != expected 1% limit
        assertTrue(plan.cap != expectedCap, "bug: 1% cap not enforced");
    }
}
