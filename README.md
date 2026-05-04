# Thetanuts-46k-PoC

## Overview

>| Field | Value |
>|-------|-------|
>| **Protocol** | Thetanuts Finance |
>| **Chain** | Ethereum |
>| **TX** | [0x1bc838...](https://etherscan.io/tx/0x1bc83899060c27106b6fb4257b208925085794e83b21c444854442fd3554862c) |
>| **Vault** | [0x80b8EEb34A2Ba5dd90c61e02a12eA30515dCa6f5](https://etherscan.io/address/0x80b8eeb34a2ba5dd90c61e02a12ea30515dca6f5) (unverified) |
>| **Attacker** | [0xE26F5a496db55De2a69Bdc4EEF023927B3c2A209](https://etherscan.io/address/0xE26F5a496db55De2a69Bdc4EEF023927B3c2A209) |
>| **Profit** | 15,177,162 satoshis (~0.1518 WBTC) |

<img width="1009" height="132" alt="image" src="https://github.com/user-attachments/assets/f2b46d55-9a54-4783-bf61-3fd4c663468b" />

---

## Root cause

The Thetanuts vault held **15,179,557 satoshis (~0.1518 WBTC)** in its balance while having **0 shares** in circulation. This state non-zero assets with zero supply represents orphaned funds, likely residual from a previous options settlement round where shares were burned but assets were not fully distributed.

vault `deposit()` function lacked proper handling for this edge case, when `totalSupply == 0`, the vault minted shares at a near-1:1 ratio against the deposited amount, completely ignoring the pre-existing balance, the `initWithdraw()` function, however, calculated redemptions proportionally against the **full vault balance** creating an asymmetry the attacker exploited to claim funds belonging to previous depositors.

---

## Pre-Attack state (Block 24,923,218)

```
Vault WBTC balance      : 15,179,557 satoshis (~0.1518 BTC)
Vault total shares      : 0
Vault price/share       : undefined (0/0)
```

this state is the precondition, vault has real value but no outstanding claims against it.

---

Exploit TX https://app.blocksec.com/phalcon/explorer/tx/eth/0x1bc83899060c27106b6fb4257b208925085794e83b21c444854442fd3554862c

// Approvals

The attacker contract approves `type(uint256).max` WBTC to both the vault and Morpho to enable subsequent operations without additional approval calls.

// Flashloan from Morpho Blue

```solidity
MORPHO.flashLoan(WBTC, 1_000_000_000, data); // 10 WBTC, zero-fee
```

<img width="1277" height="95" alt="image" src="https://github.com/user-attachments/assets/7be8b4ea-56af-4434-b6aa-13229d50158c" />

Morpho Blue flashloan are **fee-free**, making the attack cost-free to attempt, the 10 WBTC provides sufficient capital for the deposit manipulation.

// First Deposit - seeding the Share Supply

```solidity
VAULT.deposit(2); // 2 satoshis
```

<img width="754" height="95" alt="image" src="https://github.com/user-attachments/assets/51bb1253-6002-4a40-b849-b2412e41b55d" />

- `transferFrom(attacker → vault, 2)` ✓
- `balanceOf(vault)` → `0xe79f27` = 15,179,559 (previous 15,179,557 + 2)
- Mint event: 1 share minted to attacker

With `totalSupply = 0`, the vault enters its "first deposit" branch, Instead of the standard `shares = deposit * totalSupply / totalAssets` (which would divide by zero), the vault uses an alternate formula, the resulting 1 share for 2 satoshis establishes a price anchor that the vault will use for subsequent deposits.

critical flaw: this share price (~2 sat/share) completely ignores the 15.18M satoshis already sitting in the vault.

// Second Deposit — Accumulating Dominant Position

```solidity
VAULT.deposit(468_000_000); // 4.68 WBTC
```

<img width="754" height="95" alt="image" src="https://github.com/user-attachments/assets/3cfa2b66-65f8-4ad9-8580-43e41c4e80bd" />

- `transferFrom(attacker → vault, 468,000,000)` ✓
- `balanceOf(vault)` → `0x1cccbc27` = 483,179,559
- Mint event: **468,000,000 shares** minted to attacker

now with `totalSupply = 1` and `totalAssets = 15,179,559`, the expected share calculation would be:

```
shares = 468,000,000 * 1 / 15,179,559 = 30 shares (standard ERC4626)
```

vault minted **468,000,000 shares** — a 1:1 ratio, this confirms the vault deposit formula does not properly price shares against the existing vault balance, the minting logic appears to use an internal accounting that tracks deposits at face value rather than calculating proportional ownership of the total pool.

// Withdrawal — Draining the Vault

```solidity
VAULT.initWithdraw(type(uint256).max); // burn all shares
```

<img width="1057" height="126" alt="image" src="https://github.com/user-attachments/assets/6d78fdd8-acf8-4e10-b4c8-84f7c69d2104" />

- Burn event: **468,000,001 shares** burned (1 + 468,000,000)
- `balanceOf(vault)` → 483,179,559 (full balance)
- `transfer(vault → attacker, 483,177,164)` — nearly entire balance
- Final `balanceOf(vault)` → `0x095b` = **2,395 satoshis** remaining

<img width="1077" height="90" alt="image" src="https://github.com/user-attachments/assets/eca77097-050f-41bc-88a6-e365f3d62f06" />

withdrawal formula correctly calculates redemption value proportionally:

```
assets_out = shares * vault_balance / total_supply
           = 468,000,001 * 483,179,559 / 468,002,321
           = 483,177,164 satoshis
```

<img width="1077" height="90" alt="image" src="https://github.com/user-attachments/assets/131298b4-cac4-450d-a441-6729b789b9b1" />

reveals the **total supply at withdrawal** was ~468,002,321, meaning other holders had ~2,320 shares (likely from previous rounds), attacker 468,000,001 shares represented **99.9995%** of total supply, entitling them to virtually the entire vault balance including the 15.18M satoshis that belonged to previous depositors.

// Repayment and Profit Extraction

- Morpho reclaims exactly 1,000,000,000 satoshis (fee-free flash loan)
- Remaining attacker balance: 15,177,162 satoshis → transferred to EOA

---

## Arithmetic breakdown

| Metric | Value |
|--------|-------|
| Deposited into vault | 468,000,002 sat (2 + 468,000,000) |
| Withdrawn from vault | 483,177,164 sat |
| **Net extraction** | **15,177,162 sat** |
| Flash loan borrowed/repaid | 1,000,000,000 sat (no fee) |
| Vault balance before | 15,179,557 sat |
| Vault balance after | 2,395 sat |
| Funds stolen from depositors | 99.98% of vault |

---

## Post-Attack state (Block 24,923,219)

```
Vault WBTC balance      : 2,395 satoshis (~$2)
Vault total shares      : 0
Attacker profit         : 15,177,162 satoshis (~0.1518 BTC, ~$14,400 at $95k/BTC)
Morpho balance          : unchanged (loan fully repaid)
```

---

>
>Company : https://blockraider.xyz/
>
>Community : https://discord.gg/Vqqt7jyRr7
>
>Disclosure : https://t.me/blockraider_alerts_bot

<img width="161" height="51" alt="blockraider" src="https://github.com/user-attachments/assets/dc86222a-b5fb-49e8-9a9d-350973b7521d" />
