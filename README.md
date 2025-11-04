# Dapper Contracts

<p align="left">
  <img src="https://dapper-inky.vercel.app/dapper-logo.jpeg" alt="Dapper logo" height="120" />
</p>

### What is Dapper?

Dapper lets users create a term-based stake, similar to a Certificate of Deposit. You choose an amount and a duration. The protocol immediately mints the yield for your position up front, while your principal remains locked for the term.

### How it works

- **Select amount and duration**: The user chooses how much to stake and for how long.
- **Mint yield up front**: On creation, the position mints its expected yield to the user immediately.
- **Principal allocation**: During the term, the staked principal is deposited into August yield vaults to generate returns.
- **Maturity and withdrawal**: At the end of the term, the user can withdraw their principal.
- **Excess yield**: Because the vaults are expected to earn more than the principal obligation at maturity, the surplus yield is directed to the treasury.

### Key properties

- **Immediate liquidity of yield**: Users receive their yield at the start, not at the end.
- **Capital efficiency**: Principal is actively deployed in August vaults during the term.
- **Treasury accrual**: Any yield beyond the principal payout accrues to the treasury.

### Repository layout (high level)

- `src/Dapper.sol`: Core logic for creating term stakes and minting yield up front.
- `src/Vault.sol`: Integration surface for depositing principal into August yield vaults.
- `script/Dapper.s.sol`: Deployment scripts (Foundry).
- `test/`: Foundry tests.

### Developing

This repository uses Foundry.

```bash
forge install
forge build
forge test -vvv
```

### Notes

- Terms and parameters are subject to change; consult the contracts for exact calculations and constraints.
- Integrations reference August yield vaults for principal deployment.

## Security

- **Aderyn static analysis report**: see [`report.md`](report.md)
- **Slither static analysis report**: see [`report-slither.txt`](report-slither.txt)

## Addresses

- **MUSD Dapper Contract**: 0x7F3534743D998ef4a9894624b49CCd45Aa4fffD8
- **BTC Dapper Contract**: 0x6AC1C876236217C1DaDEae59B202b01eb1c7BDaF

- **MUSD Treasury Contract**: 0x92687EFb0eA6D6DC3E6B295b8f382dF8E7355420
- **BTC Treasury Contract**: 0xaBD7C734D79cDEc3dAC043968b848A44b05EDed4
