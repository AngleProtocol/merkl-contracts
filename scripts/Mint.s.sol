// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseScript } from "./utils/Base.s.sol";

/// @dev Minimal interface: any token exposing `mint(address,uint256)` works.
interface IMintable {
    function mint(address account, uint256 amount) external;
}

/// @dev Minimal ERC4626 vault interface.
interface IERC4626Vault {
    function asset() external view returns (address);
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
}

/// @notice Mint a mock token and/or approve + deposit it into an ERC4626 vault.
///
/// Generic: works with any token exposing `mint(address,uint256)` and any ERC4626
/// vault, on any chain selected at runtime via --rpc-url. Signer is taken from
/// DEPLOYER_PRIVATE_KEY (see BaseScript). The defaults below point at the mock
/// token + "Mock Test Vault" pair, but every entrypoint can be parametrized.
///
/// On some chains (e.g. OP-stack L2s) forge's local gas estimate is lower than what
/// the node actually charges, so the default 130% buffer is not enough and txs run
/// out of gas on broadcast even though the simulation passes. Pass a higher gas
/// multiplier (-g 300) and --slow (send each tx only after the previous confirms,
/// so deposit sees the allowance set by approve).
///
/// Examples:
///   # Mint the default token to the signer
///   forge script scripts/Mint.s.sol --rpc-url <chain> --broadcast -g 300
///
///   # Approve + deposit into a specific vault (token is read from vault.asset())
///   forge script scripts/Mint.s.sol --rpc-url <chain> --broadcast -g 300 --slow \
///     --sig "deposit(address,uint256)" <VAULT> 1000000000000000000000
///
///   # Mint, then approve + deposit the defaults in one go
///   forge script scripts/Mint.s.sol --rpc-url <chain> --broadcast -g 300 --slow --sig "mintAndDeposit()"
contract Mint is BaseScript {
    address internal constant DEFAULT_TOKEN = 0xAb7C5De616fE66ce2CA8592889a0dEB992B8b7D3;
    address internal constant DEFAULT_VAULT = 0x88C7982ec5332cEe47D0Cace1ADff98eBb3F839A;
    uint256 internal constant DEFAULT_AMOUNT = 1000000000000000000000; // 1000e18

    /// @notice Mint the default token to the signer.
    function run() external broadcast {
        // _mint(DEFAULT_TOKEN, broadcaster, DEFAULT_AMOUNT);
        _approveAndDeposit(DEFAULT_VAULT, DEFAULT_AMOUNT);
    }

    /// @notice Approve + deposit the defaults into the default vault.
    function deposit() external broadcast {
        _approveAndDeposit(DEFAULT_VAULT, DEFAULT_AMOUNT);
    }

    /// @notice Approve + deposit `amount` into `vault` (token is read from vault.asset()).
    function deposit(address vault, uint256 amount) external broadcast {
        _approveAndDeposit(vault, amount);
    }

    /// @notice Mint, then approve + deposit the defaults in a single broadcast.
    function mintAndDeposit() external broadcast {
        _mint(DEFAULT_TOKEN, broadcaster, DEFAULT_AMOUNT);
        _approveAndDeposit(DEFAULT_VAULT, DEFAULT_AMOUNT);
    }

    function _mint(address token, address recipient, uint256 amount) internal {
        require(token != address(0), "Mint: token address not set");

        IMintable(token).mint(recipient, amount);

        console.log("Minted %s tokens to %s", amount, recipient);
        console.log("Token: %s", token);
        console.log("Chain id: %s", block.chainid);
    }

    function _approveAndDeposit(address vault, uint256 amount) internal {
        require(vault != address(0), "Mint: vault address not set");

        address token = IERC4626Vault(vault).asset();

        IERC20(token).approve(vault, amount);
        console.log("Approved %s tokens (%s) to vault %s", amount, token, vault);

        uint256 shares = IERC4626Vault(vault).deposit(amount, broadcaster);
        console.log("Deposited %s assets, received %s shares", amount, shares);
        console.log("Receiver: %s", broadcaster);
    }
}
