// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./DelayMigratorState.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@ironblocks/firewall-consumer/contracts/FirewallConsumer.sol";

contract DelayVaultMigrator is DelayMigratorState, FirewallConsumer {
    /**
     * @dev Constructor to initialize the DelayVaultMigrator with the LockDealNFT and the old DelayVault contract.
     * @param _nft Address of the LockDealNFT contract.
     * @param _oldVault Address of the old DelayVault (IDelayVaultV1) contract.
     */
    constructor(ILockDealNFT _nft, IDelayVaultV1 _oldVault) {
        require(address(_oldVault) != address(0), "DelayVaultMigrator: Invalid old delay vault contract");
        require(address(_nft) != address(0), "DelayVaultMigrator: Invalid lock deal nft contract");
        oldVault = _oldVault;
        lockDealNFT = _nft;
    }

    /**
     * @dev Finalize the migration process by setting the new DelayVaultProvider and updating related parameters.
     * @param _newVault Address of the new DelayVaultProvider contract.
     */
    function finalize(IDelayVaultProvider _newVault) external firewallProtected {
        require(owner != address(0), "DelayVaultMigrator: already initialized");
        require(msg.sender == owner, "DelayVaultMigrator: not owner");
        require(
            ERC165Checker.supportsInterface(address(_newVault), type(IDelayVaultProvider).interfaceId),
            "DelayVaultMigrator: Invalid new delay vault contract"
        );
        newVault = _newVault;
        token = newVault.token();
        owner = address(0); // Set owner to zero address
    }
    /**
     * @dev Migrate tokens from the old DelayVault to the new DelayVaultProvider and receive DelayVaultProvider NFT.
     * Requires user approval in the old DelayVault.
     */
    function fullMigrate() external firewallProtected afterInit {
        require(oldVault.Allowance(token, msg.sender), "DelayVaultMigrator: not allowed");
        uint256 amount = getUserV1Amount(msg.sender);
        oldVault.redeemTokensFromVault(token, msg.sender, amount);
        uint256[] memory params = new uint256[](1);
        params[0] = amount;
        IERC20(token).approve(address(newVault), amount);
        newVault.createNewDelayVault(msg.sender, params);
    }

    /**
     * @dev Migrate tokens from the old DelayVault to the LockDealNFT (v3) and receive NFT providers.
     * Requires user approval in the old DelayVault.
     */
    function withdrawTokensFromV1Vault() external firewallProtected afterInit {
        require(oldVault.Allowance(token, msg.sender), "DelayVaultMigrator: not allowed");
        uint256 amount = getUserV1Amount(msg.sender);
        oldVault.redeemTokensFromVault(token, msg.sender, amount);
        uint8 theType = newVault.theTypeOf(newVault.getTotalAmount(msg.sender));
        IDelayVaultProvider.ProviderData memory providerData = newVault.getTypeToProviderData(theType);
        IERC20(token).transfer(address(lockDealNFT), amount);
        uint256 newPoolId = lockDealNFT.mintAndTransfer(msg.sender, token, amount, providerData.provider);
        uint256[] memory params = newVault.getWithdrawPoolParams(amount, theType);
        providerData.provider.registerPool(newPoolId, params);
    }

    /**
     * @dev Get the amount of tokens held by a user in the old DelayVault.
     * @param user Address of the user.
     * @return amount The amount of tokens held by the user.
     */
    function getUserV1Amount(address user) public view returns (uint256 amount) {
        (amount, , , ) = oldVault.VaultMap(token, user);
    }
}