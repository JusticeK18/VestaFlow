# VestaFlow: The Intelligent Token Vesting Protocol

```text
 ██╗   ██╗███████╗███████╗████████╗ █████╗ ███████╗██╗      ██████╗ ██╗    ██╗
 ██║   ██║██╔════╝██╔════╝╚══██╔══╝██╔══██╗██╔════╝██║     ██╔═══██╗██║    ██║
 ██║   ██║█████╗  ███████╗   ██║   ███████║█████╗  ██║     ██║   ██║██║ █╗ ██║
 ╚██╗ ██╔╝██╔══╝  ╚════██║   ██║   ██╔══██║██╔══╝  ██║     ██║   ██║██║███╗██║
  ╚████╔╝ ███████╗███████║   ██║   ██║  ██║██║     ███████╗╚██████╔╝╚███╔███╔╝
   ╚═══╝  ╚══════╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚══════╝ ╚═════╝  ╚══╝╚══╝ 
```

**VestaFlow** is an enterprise-grade, high-assurance smart contract written in **Clarity** for the **Stacks** blockchain. It provides a secure, flexible, and decentralized infrastructure for the automated distribution of tokens. Whether you are a **DAO** managing contributor rewards, a **startup** vesting founder tokens, or an **ecosystem** distributing grants, **VestaFlow** offers the precision and safety required for modern decentralized finance.

---

### **Table of Contents**

1. **Introduction**
2. **Core Features**
3. **Technical Architecture**
4. **Function Documentation**
   * 4.1 **Private Functions**
   * 4.2 **Administrative Public Functions**
   * 4.3 **Core Public Functions**
   * 4.4 **Read-Only Functions**
5. **Security and Governance**
6. **Operational Guide**
7. **Error Code Glossary**
8. **Contributing**
9. **License**

---

### **1. Introduction**

**Token vesting** is a critical component of blockchain project sustainability. It prevents sudden market saturation and ensures long-term commitment from stakeholders. **VestaFlow** moves beyond simple time-locks, offering a sophisticated state machine that handles **cliffs**, **linear unlocks**, **administrative revocation**, and **beneficiary self-sovereignty** through schedule transfers.

---

### **2. Core Features**

* **Granular Linear Vesting**: Tokens unlock on a **per-block** basis, providing a smooth distribution curve rather than "lumpy" monthly releases.
* **Cliff Protection**: Enforce a minimum holding period before any tokens become **claimable**.
* **Multi-Signature Ready Admin**: Support for multiple **administrator** addresses allows for decentralized management of the protocol.
* **Revocation and Reallocation**: A unique mechanism to reclaim **unvested tokens** from a revoked schedule and immediately assign them to a new participant—ideal for team member transitions.
* **Non-Custodial Transfers**: Beneficiaries can transfer their vesting rights to a different **principal** (e.g., moving from a software wallet to a hardware wallet).
* **Emergency Circuit Breaker**: Integrated **pause** and **resume** functionality to protect assets during unforeseen events.

---

### **3. Technical Architecture**

**VestaFlow** utilizes a **Map-Based State Store**. Each beneficiary is mapped to a unique `vesting-schedule` object. This architecture ensures **O(1)** lookup times and prevents iterative loops that could exceed block gas limits.

#### **Data Structures**
The primary state is stored in the `vesting-schedules` map:

```clarity
{
    category: (string-ascii 20),
    total-amount: uint,
    claimed-amount: uint,
    start-block: uint,
    duration: uint,
    cliff-duration: uint,
    revocable: bool,
    revoked: bool
}
```

---

### **4. Function Documentation**

#### **4.1 Private Functions**
These internal helpers power the logic and security of the contract and cannot be called directly from the outside.

* **`is-admin`** (`user principal`): Queries the `admins` map to verify if the provided principal has elevated privileges.
* **`require-unpaused`**: An assertion check used at the start of state-changing functions to ensure the contract is not in a **Paused** state.
* **`require-admin`**: An assertion check that validates `tx-sender` against the admin registry.
* **`calculate-vested-amount`** (`schedule`): The core mathematical engine. It calculates the current unlock state.
    * If **`revoked`** is true, it returns `u0`.
    * If **`current-block-height`** < `cliff-end`, it returns `u0`.
    * Otherwise, it applies the linear formula:
    
$$Vested = \frac{Total \times ElapsedBlocks}{TotalDuration}$$

#### **4.2 Administrative Public Functions**
Functions reserved for addresses with the **admin** role.

* **`add-admin`** (`new-admin principal`): Adds a new address to the admin whitelist.
* **`remove-admin`** (`admin-to-remove principal`): Removes an admin. It includes a safety check to ensure the **`contract-deployer`** can never be removed.
* **`pause-contract`**: Sets **`contract-paused`** to `true`. This halts all token claims and schedule modifications.
* **`resume-contract`**: Restores contract functionality.

#### **4.3 Core Public Functions**
The primary interaction points for administrators and beneficiaries.

* **`create-schedule`**: Registers a new vesting profile. Validates that the **`duration`** is non-zero and the **`cliff-duration`** is valid.
* **`claim`**: The main entry point for users. It calculates the **`claimable`** delta and executes an **`as-contract`** `stx-transfer`.
* **`transfer-schedule`** (`new-address principal`): Allows a user to migrate their schedule to a new principal, preserving all vesting progress.
* **`revoke-and-reallocate`**: Forfeits the **unvested** portion of a schedule. The old beneficiary keeps **vested** tokens, and a new schedule is created for the new beneficiary for the remainder.

#### **4.4 Read-Only Functions**
Gas-free queries for frontends and external integrations.

* **`get-schedule`** (`beneficiary`): Returns the full data object for a specific user.
* **`get-vested-amount`** (`beneficiary`): Returns the total amount mathematically unlocked based on block height.
* **`get-claimable-amount`** (`beneficiary`): Returns the liquid amount currently available for withdrawal.
* **`get-locked-amount`** (`beneficiary`): Returns the amount still subject to the vesting timeline.
* **`get-global-stats`**: Returns a summary of **`total-locked`** vs **`total-claimed`** tokens.

---

### **5. Security and Governance**

**VestaFlow** implements several layers of security:
1. **Check-Act-Update Pattern**: Functions validate conditions before modifying state or transferring funds.
2. **Access Control**: Strict separation between **Admin-only** and **User-only** actions.
3. **Circuit Breaker**: Capability to freeze the contract in case of a discovered vulnerability.
4. **Immutability of the Deployer Admin**: The deployer remains an admin to ensure the contract is never left without a manager.

---

### **6. Operational Guide**

#### **Deployment**
1. Deploy the contract to the **Stacks network** using **Clarinet** or **Hiro CLI**.
2. Fund the contract principal with the total amount of **STX** required for all schedules.
3. Call **`create-schedule`** for each participant.

#### **For Beneficiaries**
1. Use a Stacks-compatible wallet (**Leather**, **Xverse**).
2. Call the **`claim`** function periodically to withdraw vested tokens.
3. If moving to a new wallet, call **`transfer-schedule`** from the current wallet to the new address.

---

### **7. Error Code Glossary**

| Code | Constant | Description |
| :--- | :--- | :--- |
| **`u100`** | `err-unauthorized` | The caller lacks sufficient permissions. |
| **`u101`** | `err-schedule-exists` | This principal is already assigned a schedule. |
| **`u102`** | `err-schedule-not-found` | No vesting data exists for this address. |
| **`u103`** | `err-nothing-to-claim` | No new tokens have vested since the last claim. |
| **`u104`** | `err-invalid-params` | Parameter validation failed (e.g., duration = 0). |
| **`u105`** | `err-paused` | The contract is currently under a maintenance pause. |
| **`u109`** | `err-cannot-remove-deployer` | Attempted to remove the original contract owner. |

---

### **8. Contributing**

Contributions are essential to the open-source community. To contribute:
1. **Fork** the Project.
2. Create your **Feature Branch** (`git checkout -b feature/AmazingFeature`).
3. **Commit** your Changes (`git commit -m 'Add some AmazingFeature'`).
4. **Push** to the Branch (`git push origin feature/AmazingFeature`).
5. Open a **Pull Request**.

---

### **9. License**

**MIT License**

Copyright (c) 2026 **VestaFlow Protocol**

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

---
