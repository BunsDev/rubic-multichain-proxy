// SPDX-License-Identifier: MIT

pragma solidity >=0.8.9;

import './interfaces/IAnyswapV4Router.sol';
import 'rubic-bridge-base/contracts/architecture/OnlySourceFunctionality.sol';

error DifferentAmountSpent();
error RouterNotAvailable();

contract MultichainImpl is OnlySourceFunctionality {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // enum AnyInterface {
    //     anySwapOutUnderlying,
    //     anySwapOutNative,
    //     anySwapOut
    // }

    address public rubicProxy;

    constructor(
        uint256 _fixedCryptoFee,
        uint256 _RubicPlatformFee,
        address[] memory _routers,
        address[] memory _tokens,
        uint256[] memory _minTokenAmounts,
        uint256[] memory _maxTokenAmounts
    ) {
        initialize(_fixedCryptoFee, _RubicPlatformFee, _routers, _tokens, _minTokenAmounts, _maxTokenAmounts);
    }

    function initialize(
        uint256 _fixedCryptoFee,
        uint256 _RubicPlatformFee,
        address[] memory _routers,
        address[] memory _tokens,
        uint256[] memory _minTokenAmounts,
        uint256[] memory _maxTokenAmounts
    ) private initializer {
        __OnlySourceFunctionalityInit(
            _fixedCryptoFee,
            _RubicPlatformFee,
            _routers,
            _tokens,
            _minTokenAmounts,
            _maxTokenAmounts
        );
    }

    //     /**
    //      * @param _amountIn the input amount that the user wants to bridge
    //      * @param _dstChainId destination chain ID
    //      * @param _anyRouter the multichain router address
    //      * @param _bridgeToken the transit token address
    //      * @param _anyToken the pegged token address
    //      * @param _funcName the name of the function supported by token
    //      * @param _integrator the integrator address
    //      */
    function routerCall(
        address _anyRouter,
        address _dex,
        address _tokenIn,
        uint256 _amountIn,
        address _tokenOut,
        // uint256 _dstChainId,
        bytes calldata _swapData,
        bytes calldata _crossChainData
    ) external payable nonReentrant whenNotPaused {
        require(msg.sender == rubicProxy);
        if (!(availableRouters.contains(_anyRouter) && availableRouters.contains(_dex))) {
            revert RouterNotAvailable();
        }
        // require(_dstChainId != uint256(block.chainid), 'same chain id');

        uint256 tokenInAfter;
        (_amountIn, tokenInAfter) = _checkAmountIn(_tokenIn, _amountIn);

        SafeERC20Upgradeable.safeIncreaseAllowance(IERC20Upgradeable(_tokenIn), _dex, _amountIn);

        uint256 balanceBeforeSwap = IERC20Upgradeable(_tokenOut).balanceOf(address(this));

        AddressUpgradeable.functionCallWithValue(_dex, _swapData, msg.value);
        uint256 amountOut = IERC20Upgradeable(_tokenOut).balanceOf(address(this)) - balanceBeforeSwap;
        // TODO amount out min

        require(amountOut >= minTokenAmount[_tokenOut], 'amount must be greater than min swap amount');
        require(amountOut <= maxTokenAmount[_tokenOut], 'amount must be lower than max swap amount');
        SafeERC20Upgradeable.safeIncreaseAllowance(IERC20Upgradeable(_tokenOut), _anyRouter, amountOut);

        AddressUpgradeable.functionCallWithValue(_anyRouter, _crossChainData, msg.value);

        // if (balanceAfterTransfer - IERC20Upgradeable(_tokenIn).balanceOf(address(this)) != _amountIn) {
        //     revert DifferentAmountSpent();
        // }

        // reset allowance back to zero, just in case
        if (IERC20Upgradeable(_tokenIn).allowance(address(this), _anyRouter) > 0) {
            IERC20Upgradeable(_tokenIn).safeApprove(_anyRouter, 0);
        }
        if (IERC20Upgradeable(_tokenIn).allowance(address(this), _dex) > 0) {
            IERC20Upgradeable(_tokenIn).safeApprove(_dex, 0);
        }
    }

    function _checkAmountIn(address _tokenIn, uint256 _amountIn) internal returns (uint256, uint256) {
        uint256 balanceBeforeTransfer = IERC20Upgradeable(_tokenIn).balanceOf(address(this));
        IERC20Upgradeable(_tokenIn).safeTransferFrom(msg.sender, address(this), _amountIn);
        uint256 balanceAfterTransfer = IERC20Upgradeable(_tokenIn).balanceOf(address(this));
        _amountIn = balanceAfterTransfer - balanceBeforeTransfer;
        return (_amountIn, balanceAfterTransfer);
    }

    function _performCallAndChecks(
        address _tokenOut,
        address _dex,
        bytes calldata _data,
        uint256 _value
    ) internal returns (uint256 balanceBeforeSwap, uint256 balanceAfterSwap) {
        _tokenOut == address(0) ? balanceBeforeSwap = address(this).balance : balanceBeforeSwap = IERC20Upgradeable(
            _tokenOut
        ).balanceOf(address(this));

        AddressUpgradeable.functionCallWithValue(_dex, _data, _value);

        _tokenOut == address(0) ? balanceAfterSwap = address(this).balance : balanceAfterSwap = IERC20Upgradeable(
            _tokenOut
        ).balanceOf(address(this));
    }

    function setRubicProxy(address _rubicProxy) external onlyManagerOrAdmin {
        rubicProxy = _rubicProxy;
    }

    // function multichainCall(
    //     uint256 _amountIn,
    //     uint256 _dstChainId,
    //     IERC20Upgradeable _tokenOut,
    //     address _anyToken,
    //     address _anyRouter,
    //     AnyInterface _funcName
    // ) internal {
    //     require(availableRouters.contains(_anyRouter), 'MultichainProxy: incorrect anyRouter');
    //     if (AnyInterface.anySwapOutUnderlying == _funcName) {
    //         _tokenOut.safeIncreaseAllowance(_anyRouter, _amountIn);
    //         IAnyswapV4Router(_anyRouter).anySwapOutUnderlying(_anyToken, msg.sender, _amountIn, _dstChainId);
    //     }
    //     if (AnyInterface.anySwapOutNative == _funcName) {
    //         IAnyswapV4Router(_anyRouter).anySwapOutNative{value: _amountIn}(_anyToken, msg.sender, _dstChainId);
    //     } else {
    //         _tokenOut.safeIncreaseAllowance(_anyRouter, _amountIn);
    //         IAnyswapV4Router(_anyRouter).anySwapOut(address(_tokenOut), msg.sender, _amountIn, _dstChainId);
    //     }
    // }

    //         // TODO since not every token is underlying this might be changed
    //         require(
    //             IAnyswapV1ERC20(_anyToken).underlying() == address(bridgeToken),
    //             'MultichainProxy: incorrect anyToken address'
    //         );
}
