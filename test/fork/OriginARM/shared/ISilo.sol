// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

library IShareToken {
    struct HookSetup {
        address hookReceiver;
        uint24 hooksBefore;
        uint24 hooksAfter;
        uint24 tokenType;
    }
}

library ISilo {
    type AssetType is uint8;
    type CallType is uint8;
    //type CollateralType is uint8;

    enum CollateralType {
        Protected, // default
        Collateral
    }

    struct UtilizationData {
        uint256 collateralAssets;
        uint256 debtAssets;
        uint64 interestRateTimestamp;
    }
}

interface Silo {
    error AboveMaxLtv();
    error AmountExceedsAllowance();
    error BorrowNotPossible();
    error CollateralSiloAlreadySet();
    error CrossReentrantCall();
    error ECDSAInvalidSignature();
    error ECDSAInvalidSignatureLength(uint256 length);
    error ECDSAInvalidSignatureS(bytes32 s);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InvalidApprover(address approver);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InvalidSender(address sender);
    error ERC20InvalidSpender(address spender);
    error ERC2612ExpiredSignature(uint256 deadline);
    error ERC2612InvalidSigner(address signer, address owner);
    error EarnedZero();
    error FlashloanAmountTooBig();
    error FlashloanFailed();
    error InputCanBeAssetsOrShares();
    error InputZeroShares();
    error InvalidAccountNonce(address account, uint256 currentNonce);
    error InvalidInitialization();
    error NoLiquidity();
    error NotEnoughLiquidity();
    error NotInitializing();
    error NotSolvent();
    error NothingToWithdraw();
    error OnlyHookReceiver();
    error OnlySilo();
    error OnlySiloConfig();
    error OwnerIsZero();
    error RecipientIsZero();
    error RecipientNotSolventAfterTransfer();
    error RepayTooHigh();
    error ReturnZeroAssets();
    error ReturnZeroShares();
    error SenderNotSolventAfterTransfer();
    error SiloInitialized();
    error UnsupportedFlashloanToken();
    error ZeroAmount();
    error ZeroTransfer();

    event AccruedInterest(uint256 hooksBefore);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Borrow(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event CollateralTypeChanged(address indexed borrower);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event DepositProtected(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event EIP712DomainChanged();
    event FlashLoan(uint256 amount);
    event HooksUpdated(uint24 hooksBefore, uint24 hooksAfter);
    event Initialized(uint64 version);
    event NotificationSent(address indexed notificationReceiver, bool success);
    event Repay(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event WithdrawProtected(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event WithdrawnFeed(uint256 daoFees, uint256 deployerFees);

    receive() external payable;

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function accrueInterest() external returns (uint256 accruedInterest);
    function accrueInterestForConfig(address _interestRateModel, uint256 _daoFee, uint256 _deployerFee) external;
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool result);
    function asset() external view returns (address assetTokenAddress);
    function balanceOf(address account) external view returns (uint256);
    function balanceOfAndTotalSupply(address _account) external view returns (uint256, uint256);
    function borrow(uint256 _assets, address _receiver, address _borrower) external returns (uint256 shares);
    function borrowSameAsset(uint256 _assets, address _receiver, address _borrower) external returns (uint256 shares);
    function borrowShares(uint256 _shares, address _receiver, address _borrower) external returns (uint256 assets);
    function burn(address _owner, address _spender, uint256 _amount) external;
    function callOnBehalfOfSilo(address _target, uint256 _value, ISilo.CallType _callType, bytes memory _input)
        external
        payable
        returns (bool success, bytes memory result);
    function config() external view returns (address siloConfig);
    function convertToAssets(uint256 _shares) external view returns (uint256 assets);
    function convertToAssets(uint256 _shares, ISilo.AssetType _assetType) external view returns (uint256 assets);
    function convertToShares(uint256 _assets, ISilo.AssetType _assetType) external view returns (uint256 shares);
    function convertToShares(uint256 _assets) external view returns (uint256 shares);
    function decimals() external view returns (uint8);
    function deposit(uint256 _assets, address _receiver) external returns (uint256 shares);
    function deposit(uint256 _assets, address _receiver, ISilo.CollateralType _collateralType)
        external
        returns (uint256 shares);
    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        );
    function factory() external view returns (address);
    function flashFee(address _token, uint256 _amount) external view returns (uint256 fee);
    function flashLoan(address _receiver, address _token, uint256 _amount, bytes memory _data)
        external
        returns (bool success);
    function forwardTransferFromNoChecks(address _from, address _to, uint256 _amount) external;
    function getCollateralAndDebtTotalsStorage()
        external
        view
        returns (uint256 totalCollateralAssets, uint256 totalDebtAssets);
    function getCollateralAndProtectedTotalsStorage()
        external
        view
        returns (uint256 totalCollateralAssets, uint256 totalProtectedAssets);
    function getCollateralAssets() external view returns (uint256 totalCollateralAssets);
    function getDebtAssets() external view returns (uint256 totalDebtAssets);
    function getLiquidity() external view returns (uint256 liquidity);
    function getSiloStorage()
        external
        view
        returns (
            uint192 daoAndDeployerRevenue,
            uint64 interestRateTimestamp,
            uint256 protectedAssets,
            uint256 collateralAssets,
            uint256 debtAssets
        );
    function getTotalAssetsStorage(ISilo.AssetType _assetType) external view returns (uint256 totalAssetsByType);
    function hookReceiver() external view returns (address);
    function hookSetup() external view returns (IShareToken.HookSetup memory);
    function initialize(address _config) external;
    function isSolvent(address _borrower) external view returns (bool);
    function maxBorrow(address _borrower) external view returns (uint256 maxAssets);
    function maxBorrowSameAsset(address _borrower) external view returns (uint256 maxAssets);
    function maxBorrowShares(address _borrower) external view returns (uint256 maxShares);
    function maxDeposit(address) external pure returns (uint256 maxAssets);
    function maxFlashLoan(address _token) external view returns (uint256 maxLoan);
    function maxMint(address) external view returns (uint256 maxShares);
    function maxRedeem(address _owner, ISilo.CollateralType _collateralType) external view returns (uint256 maxShares);
    function maxRedeem(address _owner) external view returns (uint256 maxShares);
    function maxRepay(address _borrower) external view returns (uint256 assets);
    function maxRepayShares(address _borrower) external view returns (uint256 shares);
    function maxWithdraw(address _owner, ISilo.CollateralType _collateralType) external view returns (uint256 maxAssets);
    function maxWithdraw(address _owner) external view returns (uint256 maxAssets);
    function mint(uint256 _shares, address _receiver) external returns (uint256 assets);
    function mint(uint256 _shares, address _receiver, ISilo.CollateralType _collateralType)
        external
        returns (uint256 assets);
    function mint(address _owner, address, uint256 _amount) external;
    function name() external view returns (string memory);
    function nonces(address owner) external view returns (uint256);
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
    function previewBorrow(uint256 _assets) external view returns (uint256 shares);
    function previewBorrowShares(uint256 _shares) external view returns (uint256 assets);
    function previewDeposit(uint256 _assets, ISilo.CollateralType _collateralType)
        external
        view
        returns (uint256 shares);
    function previewDeposit(uint256 _assets) external view returns (uint256 shares);
    function previewMint(uint256 _shares, ISilo.CollateralType _collateralType) external view returns (uint256 assets);
    function previewMint(uint256 _shares) external view returns (uint256 assets);
    function previewRedeem(uint256 _shares) external view returns (uint256 assets);
    function previewRedeem(uint256 _shares, ISilo.CollateralType _collateralType) external view returns (uint256 assets);
    function previewRepay(uint256 _assets) external view returns (uint256 shares);
    function previewRepayShares(uint256 _shares) external view returns (uint256 assets);
    function previewWithdraw(uint256 _assets) external view returns (uint256 shares);
    function previewWithdraw(uint256 _assets, ISilo.CollateralType _collateralType)
        external
        view
        returns (uint256 shares);
    function redeem(uint256 _shares, address _receiver, address _owner) external returns (uint256 assets);
    function redeem(uint256 _shares, address _receiver, address _owner, ISilo.CollateralType _collateralType)
        external
        returns (uint256 assets);
    function repay(uint256 _assets, address _borrower) external returns (uint256 shares);
    function repayShares(uint256 _shares, address _borrower) external returns (uint256 assets);
    function silo() external view returns (address);
    function siloConfig() external view returns (address);
    function switchCollateralToThisSilo() external;
    function symbol() external view returns (string memory);
    function synchronizeHooks(uint24 _hooksBefore, uint24 _hooksAfter) external;
    function totalAssets() external view returns (uint256 totalManagedAssets);
    function totalSupply() external view returns (uint256);
    function transfer(address _to, uint256 _amount) external returns (bool result);
    function transferFrom(address _from, address _to, uint256 _amount) external returns (bool result);
    function transitionCollateral(uint256 _shares, address _owner, ISilo.CollateralType _transitionFrom)
        external
        returns (uint256 assets);
    function updateHooks() external;
    function utilizationData() external view returns (ISilo.UtilizationData memory);
    function withdraw(uint256 _assets, address _receiver, address _owner) external returns (uint256 shares);
    function withdraw(uint256 _assets, address _receiver, address _owner, ISilo.CollateralType _collateralType)
        external
        returns (uint256 shares);
    function withdrawFees() external;
}
