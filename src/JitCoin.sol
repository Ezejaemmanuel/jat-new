// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OFT} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    IOFT,
    SendParam,
    MessagingFee,
    MessagingReceipt,
    OFTReceipt
} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {OFTMsgCodec} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTMsgCodec.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";
import {Origin} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import {IOAppMsgInspector} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppMsgInspector.sol";
import {
    MessagingParams,
    MessagingFee,
    MessagingReceipt
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {IWalletFactory} from "./interfaces/IWalletFactory.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
/// @title JITCoin
/// @notice A cross-chain token implementation using LayerZero's OFT standard
/// @dev Inherits from OFT and implements custom minting and burning logic

contract JITCoin is OFT, ReentrancyGuard {
    using OFTMsgCodec for bytes;
    using OFTMsgCodec for bytes32;

    /// @notice Total amount of ETH deposited into the contract
    uint256 public totalETHDeposited;

    /// @notice Interface for the wallet factory
    IWalletFactory public walletFactory;

    // Custom Errors
    error JIT__InsufficientJITCoinBalance();
    error JIT__InsufficientETHBalance();
    error JIT__MustSendETH();
    error JIT__ETHAndTokenMismatch();
    error JIT__AmountBelowMinimum();
    error JIT__NotValidUserWallet();
    error JIT__ETHTransferFailed();
    error JIT__MintingFailed();
    error JIT__BurningFailed();
    error JIT__LayerZeroSendFailed();
    error JIT__ComposeMessageFailed();

    // Events
    event ETHDeposited(address indexed sender, uint256 amount);
    event JITCoinMinted(address indexed to, uint256 amount);
    event JITCoinBurned(address indexed from, uint256 amount);
    event ETHWithdrawn(address indexed to, uint256 amount);
    event BalanceEqualized(uint256 excessETH);
    event ComposeMessageSent(bytes32 indexed guid, address indexed to, uint256 amount);
    event ComposeMessageFailed(bytes32 indexed guid, address indexed to);

    modifier ensureBalanceEquality() {
        _;
        uint256 contractBalance = address(this).balance;
        uint256 tokenSupply = totalSupply();

        // Calculate the difference between ETH balance and token supply
        int256 balanceDifference = int256(contractBalance) - int256(tokenSupply);

        // Calculate the allowed discrepancy (0.1% of token supply)
        uint256 allowedDiscrepancy = tokenSupply * 1 / 1000;

        // Check if the absolute difference exceeds the allowed discrepancy
        if (abs(balanceDifference) > allowedDiscrepancy) {
            if (balanceDifference > 0) {
                // More ETH than tokens: mint additional tokens to the owner
                uint256 excessETH = uint256(balanceDifference);
                _mint(owner(), excessETH);
                totalETHDeposited = contractBalance;
                emit BalanceEqualized(excessETH);
            } else {
                // More tokens than ETH: burn tokens from the owner
                uint256 deficit = uint256(-balanceDifference);
                if (balanceOf(owner()) >= deficit) {
                    _burn(owner(), deficit);
                    totalETHDeposited -= deficit;
                    emit BalanceEqualized(deficit);
                } else {
                    revert JIT__InsufficientJITCoinBalance();
                }
            }
        }
    }

    // Helper function to calculate absolute value of an int256
    function abs(int256 x) private pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }
    /// @notice Ensures that the caller is a valid user wallet

    modifier onlyValidUserWallet(address _user) {
        if (!walletFactory.isValidUserWallet(_user)) {
            revert JIT__NotValidUserWallet();
        }
        _;
    }

    /// @notice Constructor for JITCoin
    /// @param _name The name of the token
    /// @param _symbol The symbol of the token
    /// @param _layerZeroEndpoint The address of the LayerZero endpoint
    /// @param _delegate The address of the delegate
    /// @param _walletFactoryAddress The address of the wallet factory
    constructor(
        string memory _name,
        string memory _symbol,
        address _layerZeroEndpoint,
        address _delegate,
        address _walletFactoryAddress
    ) OFT(_name, _symbol, _layerZeroEndpoint, _delegate) Ownable(_delegate) {
        walletFactory = IWalletFactory(_walletFactoryAddress);
    }

    /// @notice Mints JITCoin when ETH is sent to the contract
    /// @dev This function is called when ETH is sent to the contract
    function mint() public payable nonReentrant ensureBalanceEquality onlyValidUserWallet(msg.sender) {
        if (msg.value == 0) revert JIT__MustSendETH();

        uint256 amountToMint = msg.value;
        totalETHDeposited += amountToMint;
        _mint(msg.sender, amountToMint);

        emit ETHDeposited(msg.sender, amountToMint);
        emit JITCoinMinted(msg.sender, amountToMint);
    }

    /// @notice Fallback function to receive ETH and mint JITCoin
    receive() external payable {
        mint();
    }

    /// @notice Allows users to withdraw ETH by burning JITCoin
    /// @param amount The amount of JITCoin to burn and ETH to withdraw
    function withdraw(uint256 amount) external ensureBalanceEquality {
        if (balanceOf(msg.sender) < amount) revert JIT__InsufficientJITCoinBalance();
        if (address(this).balance < amount) revert JIT__InsufficientETHBalance();
        totalETHDeposited -= amount;

        _burn(msg.sender, amount);
        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) revert JIT__ETHTransferFailed();
        emit JITCoinBurned(msg.sender, amount);
        emit ETHWithdrawn(msg.sender, amount);
    }

    /// @notice Sends JITCoin to another chain
    /// @dev Overrides the OFT send function to include custom logic
    /// @param _sendParam The parameters for sending tokens
    /// @param _messagingFee The fee for messaging
    /// @param _refundAddress The address to refund any excess fees
    /// @return receipt The messaging receipt
    /// @return oftReceipt The OFT receipt
    function send(SendParam calldata _sendParam, MessagingFee calldata _messagingFee, address _refundAddress)
        public
        payable
        virtual
        override
        ensureBalanceEquality
        returns (MessagingReceipt memory receipt, OFTReceipt memory oftReceipt)
    {
        if (balanceOf(msg.sender) < _sendParam.amountLD) revert JIT__InsufficientJITCoinBalance();
        if (address(this).balance < _sendParam.amountLD) revert JIT__InsufficientETHBalance();

        (uint256 amountSentLD, uint256 amountReceivedLD) =
            _debit(_sendParam.amountLD, _sendParam.minAmountLD, _sendParam.dstEid);
        totalETHDeposited -= amountSentLD;

        (bytes memory message, bytes memory options) = _buildMsgAndOptions(_sendParam, amountReceivedLD);

        MessagingReceipt memory _receipt = _lzSend(_sendParam.dstEid, message, options, _messagingFee, _refundAddress);
        receipt = _receipt;
        oftReceipt = OFTReceipt(amountSentLD, amountReceivedLD);
        emit OFTSent(receipt.guid, _sendParam.dstEid, msg.sender, amountSentLD, amountReceivedLD);

        return (receipt, oftReceipt);
    }

    /// @notice Handles the receipt of tokens from another chain
    /// @dev Overrides the OFT _lzReceive function to include custom logic
    /// @param _origin The origin of the transfer
    /// @param _guid The globally unique identifier of the message
    /// @param _message The message containing transfer details

    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address, /*_executor */
        bytes calldata /*_extraData */
    ) internal virtual override {
        address toAddress = _message.sendTo().bytes32ToAddress();
        uint256 amountReceivedLD = _credit(toAddress, _toLD(_message.amountSD()), _origin.srcEid);

        if (_message.isComposed()) {
            bytes memory composeMsg =
                OFTComposeMsgCodec.encode(_origin.nonce, _origin.srcEid, amountReceivedLD, _message.composeMsg());
            try endpoint.sendCompose(toAddress, _guid, 0, composeMsg) {
                emit ComposeMessageSent(_guid, toAddress, amountReceivedLD);
            } catch {
                emit ComposeMessageFailed(_guid, toAddress);
            }
        }

        emit OFTReceived(_guid, _origin.srcEid, toAddress, amountReceivedLD);
    }

    /// @notice Debits tokens from the sender's account for cross-chain transfer
    /// @dev Overrides the OFT _debit function to include custom logic
    /// @param _amountLD The amount to debit in local decimals
    /// @param _minAmountLD The minimum amount to debit in local decimals
    /// @return amountSentLD The amount sent in local decimals
    /// @return amountReceivedLD The amount received in local decimals
    function _debit(uint256 _amountLD, uint256 _minAmountLD, uint32 _dstEid)
        internal
        virtual
        override
        ensureBalanceEquality
        returns (uint256 amountSentLD, uint256 amountReceivedLD)
    {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);
        totalETHDeposited -= amountSentLD;
        _burn(msg.sender, amountSentLD);
        emit JITCoinBurned(msg.sender, amountSentLD);
        return (amountSentLD, amountReceivedLD);
    }

    function _debitView(uint256 _amountLD, uint256 _minAmountLD, uint32 /*_dstEid*/ )
        internal
        view
        override
        returns (uint256 amountSentLD, uint256 amountReceivedLD)
    {
        // @dev Remove the dust so nothing is lost on the conversion between chains with different decimals for the token.
        amountSentLD = _removeDust(_amountLD);
        // @dev The amount to send is the same as amount received in the default implementation.
        amountReceivedLD = amountSentLD;

        // @dev Check for slippage.
        if (amountReceivedLD < _minAmountLD) {
            revert SlippageExceeded(amountReceivedLD, _minAmountLD);
        }
    }

    /// @notice Credits tokens to the recipient's account after cross-chain transfer
    /// @dev Overrides the OFT _credit function to include custom logic
    /// @param _to The address to credit tokens to
    /// @param _amountLD The amount to credit in local decimals
    /// @return amountReceivedLD The amount received in local decimals
    function _credit(address _to, uint256 _amountLD, uint32 /*_srcEid*/ )
        internal
        virtual
        override
        ensureBalanceEquality
        returns (uint256 amountReceivedLD)
    {
        amountReceivedLD = _amountLD;
        totalETHDeposited += amountReceivedLD;

        _mint(_to, amountReceivedLD);
        emit JITCoinMinted(_to, amountReceivedLD);
        return amountReceivedLD;
    }

    /// @notice Gets the current ETH balance of the contract
    /// @return The current ETH balance of the contract
    function getContractETHBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
