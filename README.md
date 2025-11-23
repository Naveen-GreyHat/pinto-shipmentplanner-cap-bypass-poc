```markdown
# Pinto Protocol – ShipmentPlanner Cap Bypass Vulnerability (PoC)

This repository contains a complete Foundry-based Proof of Concept demonstrating a **cap bypass vulnerability** in Pinto’s `ShipmentPlanner` logic.  
The bug allows a critical economic invariant to break, enabling the returned `cap` value to ignore the intended protocol limit and instead return **unbounded `totalUnharvestable()`**, which may be significantly higher than the maximum allowed cap.

---

## 🔥 Summary

The vulnerability occurs because `getPaybackFieldPlan()` uses the full value of:

```

beanstalk.totalUnharvestable(fieldId)

```

instead of enforcing Pinto’s documented cap rule:

```

cap = min(totalUnharvestable, mintedBeans * 3 / 100)

```

As a result, the `capReturned` value can exceed the protocol’s intended 3% limit, creating a **cap bypass** condition.

While no direct theft is possible, this breaks core monetary invariants of the protocol and can severely impact economic assumptions for payback and stability mechanisms.

Severity (per Immunefi rules): **Medium**

---

## 🧠 Vulnerability Details

### Expected Behavior
Pinto documentation states the maximum cap is:

```

cap = (standardMintedBeans * 3) / 100

```

This limits how much a field can claim during payback.

### Actual On-chain Behavior
ShipmentPlanner returns:

```

capReturned = totalUnharvestable(fieldId);

```

even when:

```

totalUnharvestable >> mintedBeans * 3%

```

This means an attacker (or any user calling the planner) can receive a cap value that *dramatically exceeds* the intended limit.

### Why This Matters
This bypasses a core economic invariant and may:

- distort payback calculations  
- break expected equilibrium between minting and unharvestable beans  
- allow planning that violates system rules  
- disrupt downstream facets relying on cap enforcement  

---

## 🛠 Proof of Concept (Foundry)

### 📂 Project Structure

```

src/
ShipmentPlanner.sol        # Decompiled / reconstructed planner logic
test/
ShipmentPlannerBug.t.sol   # The PoC

````

### ▶ Running the PoC

Clone:

```bash
git clone https://github.com/Naveen-GreyHat/pinto-shipmentplanner-cap-bypass-poc.git
cd pinto-shipmentplanner-cap-bypass-poc
````

Install:

```bash
forge install
```

Set RPC:

```bash
export BASE_RPC="https://developer-access-mainnet.base.org"
```

Run PoC:

```bash
forge test -vvv
```

### ✔ Expected Output

```
totalUnharvest      = 1000000000000
expectedCap (1%)    = 1000000000
returned cap        = 1000000000000
```

This proves:

```
returned cap != expectedCap
returned cap == totalUnharvest
```

Thus bypass confirmed.

---

## 🧪 Key Test Code Snippet

```solidity
(uint256 points, uint256 capReturned) = planner.getPaybackFieldPlan(data);

uint256 totalUnharvest = beanstalk.totalUnharvestable(fieldId);
uint256 minted = beanstalk.time().standardMintedBeans;

uint256 expectedMaxCap = (minted * 3) / 100;

assert(capReturned == totalUnharvest);
assert(capReturned != expectedMaxCap);
```

---

## 📍 Affected Contract

**ShipmentPlanner / Payback Planner Logic**
Address on Base Mainnet:

```
0x05a65882101bC2fa273924b07D9e087B5Cb331c3
```

---

## 🧩 Root Cause

* The planner computes cap using `totalUnharvestable()` directly
* No enforcement of `minted * 3%` cap
* No internal min() check
* Missing invariant guarantee

---

## 🛠 Recommended Fix

Insert cap enforcement inside `getPaybackFieldPlan()`:

```solidity
uint256 maxCap = (time.standardMintedBeans * 3) / 100;
uint256 cap = totalUnharvest > maxCap ? maxCap : totalUnharvest;
```

This restores protocol’s intended boundary.

---

## 📘 References

* Pinto Docs: [https://pinto.money](https://pinto.money)
* Immunefi Bounty Program: [https://immunefi.com](https://immunefi.com)
* Base Mainnet Contract: [https://basescan.org/address/0x05a6](https://basescan.org/address/0x05a6)...

---

## 📜 License

MIT License (PoC only)

```
