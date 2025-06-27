// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IPermit {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        bytes memory signature
    ) external;

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function nonces(address owner) external view returns (uint256);
}