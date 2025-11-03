// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract Vault is ERC4626 {
    constructor(address _depositToken, string memory _name, string memory _symbol) ERC20(_name, _symbol) ERC4626(IERC20(_depositToken)) {}
}