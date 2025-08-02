# AutomationHook

**AutomationHook** is a Solidity smart contract for automating on-chain actions in response to Uniswap v4 trading activity. It enables permissionless automation by invoking a configurable target contract on every swap, using pool trading as a decentralized "power source" for automation. This helps keep liquidity active and concentrated, making pools more attractive to arbitrageurs and traders.

## Key Features

- **Generic Automation:** Call any target contract on every swap, not limited to a specific manager.
- **Automated Rebalancing:** Optionally integrates with a manager contract to keep liquidity ranges narrow and active, maximizing fee generation and arbitrage opportunities.
- **Configurable:** Owner can set or update both the automation target and the manager contract.
- **Uniswap v4 Hook Integration:** Implements Uniswap v4 hook permissions for `beforeSwap` and `afterSwap`.

## How It Works

- **beforeSwap:** Calls the configured target contract on every swap, enabling arbitrary on-chain actions.
- **afterSwap:** If a manager is set, checks if the pool is out of range and triggers a rebalance to keep liquidity active and concentrated.

## Example Use Cases

- **Liquidity Management:** By setting a manager contract (see `Rebalance.sol`), the hook can automatically rebalance liquidity positions, keeping them narrow and attractive for arbitrageurs, which helps maintain active trading and fee generation.
- **Custom Automation:** Set the target to any contract to trigger custom logic on every swap.

## Usage

1. Deploy `AutomatizationHook` with the admin address.
2. Set the target contract using `changeTarget(address)`.
3. (Optional) Set the manager contract using `changeManager(address)`.
4. The contract will automatically call the target on every swap, and rebalance liquidity if a manager is set and the pool is out of range.

## Manager Interface

If using automated rebalancing, the manager contract should implement the required interface. See `Rebalance.sol` for an example implementation.

## Security

- Only the owner can change the target and manager addresses.
- The contract relies on the external manager for rebalancing logic.

## Considerations

- It is intended to be a "free" source of automation, to make it posible a good enough amount of liquidity is needed to avoid IL (Around >2k usd)

## File Structure

- `AutomationHook.sol`: Main automation contract.
- `Rebalance.sol`: Example manager contract for automated liquidity rebalancing.

## License

MIT (see individual files for details)

> **Note:** This contract is intended for advanced Uniswap v4 automation and may require additional configuration for production deployments. Always review and test thoroughly before use.
