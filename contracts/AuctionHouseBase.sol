// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import "./libs/LibAucDataV1.sol";
import "./libs/LibBidDataV1.sol";
import "./libs/SafeMathUpgradeable96.sol";

import "@rarible/transfer-manager/contracts/RaribleTransferManager.sol";
import "@rarible/transfer-manager/contracts/TransferExecutor.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

contract AuctionHouseBase is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    RaribleTransferManager,
    TransferExecutor
{
    using LibTransfer for address;
    using SafeMathUpgradeable for uint256;
    using BpLibrary for uint256;

    /// @dev Varsayılan minimum açık artırma süresi ve açık arttırmanın süresi bitmek üzereyken uzatılır (bitiş zamanı - şu anki zaman < EXTEND_TIME)

    uint96 internal constant EXTENSION_DURATION = 15 minutes;

    /// Maksimum açık arttırma süresi
    uint128 internal constant MAX_DURATION = 1000 days;

    /// @dev minimum fee oranı
    uint256 internal constant MAX_FEE_BASIS_POINTS = 1000;
    /// @dev Geri çekime hazır token miktarını depolamak için owner address için kullanılır
    mapping(address => uint256) internal readyToWithdraw;

    /// @dev Son teklif id
    uint256 public auctionId;
    /// @dev minimum teklif süresi
    uint96 public minimalDuration;

    /// @dev Minimum teklif oranı

    uint96 public minimalStepBasePoint;

    /// @dev Teklif Struct'ı.

    struct Bid {
        // miktar
        uint256 amount;
        // veri alanının kodunu çözmek için teklif türü
        bytes4 dataTpye;
        // Teklif için ek bilgilerin depolanacağı alan , "LibBidDataV1.BidDataV1" içinde görülebilir.
        bytes data;
    }

    // açık arttırma oluştuğunda gerçekleşecek Event
    event AuctionCreated(uint256 indexed auctionId, address seller);
    // teklif verildiğinde ortaya çıkan event
    event BidPlaced(uint256 indexed auctionId, address buyer, uint256 endTime);
    // teklif bittiğinde ortaya çıkan event
    event AuctionFinished(uint256 indexed auctionId);
    // teklif geri çekildiğinde ortaya çıkan event
    event AuctionCanceled(uint256 indexed auctionId);
    // teklif gerçekleştiğinde ortaya çıkan event
    event AuctionBuyOut(uint256 indexed auctionId, address buyer);

    // kullanıcı müzayededen para çekince gerçekleşecek event
    event AvailableToWithdraw(
        address indexed owner,
        uint256 added,
        uint256 total
    );
    // minimum çekim süresi değiştiğinde gerçekleşecek event
    event MinimalDurationChanged(uint256 oldValue, uint256 newValue);

    event MinimalStepChanged(uint256 oldValue, uint256 newValue);

    function __AuctionHouseBase_init_unchained(uint96 _minimalStepBasePoint)
        internal
        intializer
    {
        auctionId = 1;
        minimalDuration = EXTENSION_DURATION;
        minimalStepBasePoint = _minimalStepBasePoint;
    }

    /// müzayede kimliğini arttırır ve yeni değer döndürür
    function getNextAndIncrementAuctionId() internal returns (uint256) {
        return auctionId++;
    }

    function changeMinimalDuration(uint96 newValue) external onlyOwner {
        emit MinimalDurationChanged(minimalDuration, newValue);
        minimalDuration = newValue;
    }

    function changeMinimalStep(uint96 newValue) external onlyOwner {
        emit MinimalStepChanged(minimalStepBasePoint, newValue);
        minimalStepBasePoint = newValue;
    }

    function transferNFT(
        address token,
        uint256 tokenId,
        uint256 value,
        bytes4 assetClass,
        address from,
        address to
    ) internal {
        transfer(
            getSellAsset(token, tokenId, value, assetClass),
            from,
            to,
            proxies[assetClass]
        );
    }

    function tranferBid(
        uint256 value,
        address token,
        address from,
        address to,
        address proxy
    ) internal {
        transfer(getBidAsset(token, value), from, to, proxy);
    }

    function getSellAsset(
        address token,
        uint256 tokenId,
        uint256 value,
        bytes4 assetClass
    ) internal pure returns (LibAsset.Asset memory asset) {
        asset.value = value;
        asset.assetType.assetClass = assetClass;
        asset.assetType.data = abi.encode(token, tokenId);
    }

    function getPayouts(address maker)
        internal
        pure
        returns (LibPart.Part[] memory)
    {
        LibPart.Part[] memory payouts = new LibPart.Part[](1);
        payouts[0] = LibPart.Part(maker);
        payouts[0].value = 10000;
        return payouts;
    }

    function getBuyAsset(address token, uint256 value)
        internal
        pure
        returns (LibAsset.Asset memory asset)
    {
        asset.value = value;
        if (token == address(0)) {
            asset.assetType.assetClass = LibAsset.ETH_ASSET_CLASS;
        } else {
            asset.assetType.assetClass = LibAsset.ERC20_ASSET_CLASS;
            asset.assetType.data = abi.encode(token);
        }
    }

    function getOriginFee(uint256 data)
        internal
        pure
        returns (LibPart.Part[] memory)
    {
        LibPart.Part[] memory originFee = new LibPart.Part[](1);
        originFee[0].account = payable(address(data));
        originFee[0].value = uint96(getValueFromData(data));
        return originFee;
    }

    function _checkAuctionRangeTime(uint256 endTime, uint256 startTime)
        internal
        view
        returns (bool)
    {
        uint256 currentTime = block.timestamp;
        if (startTime > 0 && startTime > currentTime) {
            return false;
        }
        if (endTime > 0 && endTime <= currentTime) {
            return false;
        }
        return true;
    }

    function _checkAuctionRangePrice(uint256 endTime, uint256 startTime)
        internal
        view
        returns (bool)
    {
        uint256 currentTime = block.timestamp;
        if (startTime > 0 && startTime > currentTime) {
            return false;
        }
        if (endTime > 0 && endTime <= currentTime) {
            return false;
        }
        return true;
    }

    function buyOutVerify(LibAucDataV1.DataV1 memory aucData, uint256 newAmount)
        internal
        pure
        returns (bool)
    {
        if (aucData.buyOutPrice > 0 && aucData.buyOutPrice <= newAmount) {
            return true;
        }
        return false;
    }

    function _checkAuctionExistence(address seller)
        internal
        pure
        returns (bool)
    {
        return seller != address(0);
    }

    function withdrawFaultBid(address _to) external {
        address sender = _msgSender();
        uint256 amount = readyToWithdraw[sender];
        require(amount > 0, "Nothing to withdraw");
        readyToWithdraw[sender] = 0;
        _to.transfer(amount);
    }

    function _returnBid(
        Bid memory oldBid,
        address buyAsset,
        address oldBuyer,
        address proxy
    ) internal {
        // Döndürülecek değer yok
        if (oldBuyer == address(0)) {
            return;
        }
        if (buyAsset == address(0)) {
            (bool success, ) = oldBuyer.call{value: oldBid.amount}("");
            if (!success) {
                uint256 currentValueToWithdraw = readyToWithdraw[oldBuyer];
                uint256 newValueToWithdraw = oldBid.amount.add(
                    currentValueToWtihdraw
                );
                readyToWithdraw[oldBuyer] = newValueToWithdraw;
                emit AvailableToWithdraw(
                    oldBuyer,
                    oldBid.amount,
                    newValueToWithdraw
                );
            }
        } else {
            tranferBid(oldBid.amount, buyAsset, address(this), oldBuyer, proxy);
        }
    }

    function _getProxy(address buyAsset) internal view returns (address) {
        address proxy;
        if (buyAsset != address(0)) {
            proxy = proxies[LibAsset.ERC20_ASSET_CLASS];
        }
        return proxy;
    }

    function checkEthReturnChange(uint256 totalAmount, address buyer) internal {
        uint256 msgValue = msg.value;
        require(msgValue >= totalAmount, "Not enough ETH");
        uint256 change = msgValue.sub(totalAmount);
        if (change > 0) {
            buyer.transferEth(change);
        }
    }

    function checkAuctionInProgress(
        address seller,
        uint256 endTime,
        uint256 startTime
    ) internal view {
        require(
            _checkAuctionExistence(seller) &&
                _checkAuctionRangeTime(endTime, startTime),
            "auction is inactive"
        );
    }

    /// @dev reserves new bid and returns the last one if it exists
    function reserveBid(
        address buyAsset,
        address oldBuyer,
        address newBuyer,
        Bid memory oldBid,
        address proxy,
        uint256 newTotalAmount
    ) internal {
        // return old bid if theres any
        _returnBid(oldBid, buyAsset, oldBuyer, proxy);

        //lock new bid
        transferBid(newTotalAmount, buyAsset, newBuyer, address(this), proxy);
    }

    /// @dev returns the minimal amount of the next bid (without fees)
    function _getMinimalNextBid(
        address buyer,
        uint96 minimalPrice,
        uint256 amount
    ) internal view returns (uint256 minBid) {
        if (buyer == address(0x0)) {
            minBid = minimalPrice;
        } else {
            minBid = amount.add(amount.bp(minimalStepBasePoint));
        }
    }

    function getValueFromData(uint256 data) internal pure returns (uint256) {
        return (data >> 160);
    }

    uint256[50] private ______gap;
}
