// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Minimal IERC20 just for totalSupply
interface IERC20 {
    function totalSupply() external view returns (uint256);
}

// Minimal Season struct (only field we care about)
struct Season {
    uint32 current;
    uint32 lastSop;
    uint32 lastSopSeason;
    uint32 rainStart;
    bool raining;
    uint32 sunriseBlock;
    bool abovePeg;
    uint64 start;
    uint32 period;
    uint32 timestamp;
    uint256 standardMintedBeans;
}

// Same ShipmentPlan struct as Pinto
struct ShipmentPlan {
    uint256 points;
    uint256 cap;
}

// Beanstalk interface (trimmed)
interface IBeanstalk {
    function isHarvesting(uint256 fieldId) external view returns (bool);
    function totalUnharvestable(uint256 fieldId) external view returns (uint256);
    function fieldCount() external view returns (uint256);
    function time() external view returns (Season memory);
}

// Payback interface (trimmed)
interface IPayback {
    function siloRemaining() external view returns (uint256);
    function barnRemaining() external view returns (uint256);
}

/**
 * @title ShipmentPlanner (copied from Pinto mainnet, trimmed)
 * @notice Yahi contract me bug hai: getPaybackFieldPlan ka cap ignore ho raha hai.
 */
contract ShipmentPlanner {
    uint256 internal constant PRECISION = 1e18;

    uint256 constant FIELD_POINTS = 48_500_000_000_000_000;
    uint256 constant SILO_POINTS = 48_500_000_000_000_000;
    uint256 constant BUDGET_POINTS = 3_000_000_000_000_000;
    uint256 constant PAYBACK_FIELD_POINTS = 1_000_000_000_000_000;
    uint256 constant PAYBACK_CONTRACT_POINTS = 2_000_000_000_000_000;

    uint256 constant SUPPLY_BUDGET_FLIP = 1_000_000_000e6;

    IBeanstalk public beanstalk;
    IERC20 public bean;

    constructor(address beanstalkAddress, address beanAddress) {
        beanstalk = IBeanstalk(beanstalkAddress);
        bean = IERC20(beanAddress);
    }

    /**
     * @notice Pinto mainnet ka vulnerable function
     * @dev Niche bug: last line me `cap` ki jagah fir se totalUnharvestable return kar diya.
     */
    function getPaybackFieldPlan(
        bytes memory data
    ) external view returns (ShipmentPlan memory shipmentPlan) {
        uint256 paybackRatio = PRECISION - budgetMintRatio();
        require(paybackRatio > 0);

        (uint256 fieldId, address paybackContract) = abi.decode(data, (uint256, address));
        (bool success, uint256 siloRemaining, uint256 barnRemaining) = paybacksRemaining(
            paybackContract
        );
        // If the contract does not exist yet.
        if (!success) {
            return
                ShipmentPlan({
                    points: PAYBACK_FIELD_POINTS,
                    cap: beanstalk.totalUnharvestable(fieldId)
                });
        }

        // Add strict % limits. Silo will be paid off first.
        uint256 points;
        uint256 cap = beanstalk.totalUnharvestable(fieldId);
        if (barnRemaining == 0) {
            points = PAYBACK_FIELD_POINTS + PAYBACK_CONTRACT_POINTS;
            cap = min(cap, (beanstalk.time().standardMintedBeans * 3) / 100); // 3%
        } else if (siloRemaining == 0) {
            points = PAYBACK_FIELD_POINTS + (PAYBACK_CONTRACT_POINTS * 1) / 4;
            cap = min(cap, (beanstalk.time().standardMintedBeans * 15) / 1000); // 1.5%
        } else {
            points = PAYBACK_FIELD_POINTS;
            cap = min(cap, (beanstalk.time().standardMintedBeans * 1) / 100); // 1%
        }

        // Scale points by distance to threshold.
        points = (points * paybackRatio) / PRECISION;

        // ❌ BUG YAHAN HAI:
        // yahan `cap` return hona chahiye tha, lekin fir se totalUnharvestable(fieldId) bhej diya.
        return ShipmentPlan({points: points, cap: beanstalk.totalUnharvestable(fieldId)});
    }

    function budgetMintRatio() private view returns (uint256) {
        uint256 beanSupply = bean.totalSupply();
        uint256 seasonalMints = beanstalk.time().standardMintedBeans;

        // 0% to budget.
        if (beanSupply > SUPPLY_BUDGET_FLIP + seasonalMints) {
            return 0;
        }
        // 100% to budget.
        else if (beanSupply + seasonalMints <= SUPPLY_BUDGET_FLIP) {
            return PRECISION;
        }
        // Partial budget allocation.
        else {
            uint256 remainingBudget = SUPPLY_BUDGET_FLIP - (beanSupply - seasonalMints);
            return (remainingBudget * PRECISION) / seasonalMints;
        }
    }

    function paybacksRemaining(
        address paybackContract
    ) private view returns (bool totalSuccess, uint256 siloRemaining, uint256 barnRemaining) {
        (bool success, bytes memory returnData) = paybackContract.staticcall(
            abi.encodeWithSelector(IPayback.siloRemaining.selector)
        );
        totalSuccess = success;
        siloRemaining = success ? abi.decode(returnData, (uint256)) : 0;
        (success, returnData) = paybackContract.staticcall(
            abi.encodeWithSelector(IPayback.barnRemaining.selector)
        );
        totalSuccess = totalSuccess && success;
        barnRemaining = success ? abi.decode(returnData, (uint256)) : 0;
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}

/* ---------------- MOCKS for local PoC ---------------- */

contract MockBeanstalk is IBeanstalk {
    uint256 public _fieldCount = 10;
    mapping(uint256 => uint256) public unharvest;
    Season internal _season;
    bool public harvesting = true;

    function setTotalUnharvest(uint256 fieldId, uint256 value) external {
        unharvest[fieldId] = value;
    }

    function setSeasonMint(uint256 stdMint) external {
        _season.standardMintedBeans = stdMint;
    }

    function setHarvesting(bool v) external {
        harvesting = v;
    }

    function isHarvesting(uint256) external view override returns (bool) {
        return harvesting;
    }

    function totalUnharvestable(uint256 fieldId) external view override returns (uint256) {
        return unharvest[fieldId];
    }

    function fieldCount() external view override returns (uint256) {
        return _fieldCount;
    }

    function time() external view override returns (Season memory) {
        return _season;
    }
}

contract MockPayback is IPayback {
    uint256 public _siloRemaining;
    uint256 public _barnRemaining;

    function setRemaining(uint256 s, uint256 b) external {
        _siloRemaining = s;
        _barnRemaining = b;
    }

    function siloRemaining() external view override returns (uint256) {
        return _siloRemaining;
    }

    function barnRemaining() external view override returns (uint256) {
        return _barnRemaining;
    }
}

contract MockBean is IERC20 {
    uint256 private _supply;

    constructor(uint256 supply) {
        _supply = supply;
    }

    function totalSupply() external view override returns (uint256) {
        return _supply;
    }

    function setSupply(uint256 supply) external {
        _supply = supply;
    }
}
