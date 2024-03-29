pragma solidity ^0.4.24;

import "./SafeMath.sol";
import "./ERC721.sol";
import "./interfaces/ERC223.sol";
import "./interfaces/ITokenUse.sol";
import "./interfaces/IActivity.sol";
import "./interfaces/ISettingsRegistry.sol";
import "./interfaces/IInterstellarEncoder.sol";
import "./interfaces/IActivityObject.sol";
import "./SettingIds.sol";
import "./DSAuth.sol";

contract TokenUse is DSAuth, ITokenUse, SettingIds {
    using SafeMath for *;

    event OfferCreated(uint256 indexed tokenId, uint256 duration, uint256 price, address acceptedActivity, address owner);
    event OfferCancelled(uint256 tokenId);
    event OfferTaken(uint256 indexed tokenId, address from, address owner, uint256 now, uint256 endTime);
    event ActivityAdded(uint256 indexed tokenId, address activity, uint256 endTime);
    event ActivityRemoved(uint256 indexed tokenId, address activity);
    event TokenUseRemoved(uint256 indexed tokenId, address owner, address user, address activity);

    struct UseStatus {
        address user;
        address owner;
        uint48  startTime;
        uint48  endTime;
        uint256 price;  // PI per second.
        address acceptedActivity;   // can only be used in this activity.
    }

    struct UseOffer {
        address owner;
        uint48 duration;
        // total price of hiring mft for full duration
        uint256 price;
        address acceptedActivity;   // If 0, then accept any activity
    }

    struct CurrentActivity {
        address activity;
        uint48 endTime;
    }

    bool private singletonLock = false;

    ISettingsRegistry public registry;
    mapping (uint256 => UseStatus) public tokenId2UseStatus;
    mapping (uint256 => UseOffer) public tokenId2UseOffer;

    mapping (uint256 => CurrentActivity ) public tokenId2CurrentActivity;

    /*
     *  Modifiers
     */
    modifier singletonLockCall() {
        require(!singletonLock, "Only can call once");
        _;
        singletonLock = true;
    }

    function initializeContract(ISettingsRegistry _registry) public singletonLockCall {
        owner = msg.sender;
        emit LogSetOwner(msg.sender);

        registry = _registry;
    }

    // false if it is not in useStage
    // based on data in TokenUseStatus
    function isObjectInHireStage(uint256 _tokenId) public view returns (bool) {
        if (tokenId2UseStatus[_tokenId].user == address(0)) {
            return false;
        }
        
        return tokenId2UseStatus[_tokenId].startTime <= now && now <= tokenId2UseStatus[_tokenId].endTime;
    }

    // by check this function
    // you can know if an nft is ok to addActivity
    // based on data in CurrentActivity
    function isObjectReadyToUse(uint256 _tokenId) public view returns (bool) {

        if(tokenId2CurrentActivity[_tokenId].endTime == 0) {
            return tokenId2CurrentActivity[_tokenId].activity == address(0);
        } else {
            return now > tokenId2CurrentActivity[_tokenId].endTime;
        }
    }


    function getTokenUser(uint256 _tokenId) public view returns (address) {
        return tokenId2UseStatus[_tokenId].user;
    }

    function receiveApproval(address _from, uint _tokenId, bytes _data) public {
        if(msg.sender == registry.addressOf(CONTRACT_OBJECT_OWNERSHIP)) {
            uint256 duration;
            uint256 price;
            address acceptedActivity;
            assembly {
                let ptr := mload(0x40)
                calldatacopy(ptr, 0, calldatasize)
                duration := mload(add(ptr, 132))
                price := mload(add(ptr, 164))
                acceptedActivity := mload(add(ptr, 196))
            }

            // already approve that msg.sender == ownerOf(_tokenId)

            _createTokenUseOffer(_tokenId, duration, price, acceptedActivity, _from);
        }
    }


    // need approval from msg.sender
    function createTokenUseOffer(uint256 _tokenId, uint256 _duration, uint256 _price, address _acceptedActivity) public {
        require(ERC721(registry.addressOf(CONTRACT_OBJECT_OWNERSHIP)).ownerOf(_tokenId) == msg.sender, "Only can call by the token owner.");

        _createTokenUseOffer(_tokenId, _duration, _price, _acceptedActivity, msg.sender);
    }

    // TODO: be careful with unit of duration and price
    // remember to deal with unit off chain
    function _createTokenUseOffer(uint256 _tokenId, uint256 _duration, uint256 _price, address _acceptedActivity, address _owner) internal {
        require(isObjectReadyToUse(_tokenId), "No, it is still in use.");
        require(tokenId2UseOffer[_tokenId].owner == 0, "Token already in another offer.");
        require(_price >= 1 ether, "price must larger than 1 PI.");
        require(_duration >= 7 days);

        ERC721(registry.addressOf(CONTRACT_OBJECT_OWNERSHIP)).transferFrom(_owner, address(this), _tokenId);

        tokenId2UseOffer[_tokenId] = UseOffer({
            owner: _owner,
            duration: uint48(_duration),
            price : _price,
            acceptedActivity: _acceptedActivity
        });

        emit OfferCreated(_tokenId,_duration, _price, _acceptedActivity, _owner);
    }

    function cancelTokenUseOffer(uint256 _tokenId) public {
        require(tokenId2UseOffer[_tokenId].owner == msg.sender, "Only token owner can cancel the offer.");

        ERC721(registry.addressOf(CONTRACT_OBJECT_OWNERSHIP)).transferFrom(address(this), msg.sender,  _tokenId);

        delete tokenId2UseOffer[_tokenId];

        emit OfferCancelled(_tokenId);
    }

    function takeTokenUseOffer(uint256 _tokenId) public {
        uint256 expense = uint256(tokenId2UseOffer[_tokenId].price);

        tokenId2UseOffer[_tokenId].owner.transfer(expense);

        _takeTokenUseOffer(_tokenId, msg.sender);
    }

    function _takeTokenUseOffer(uint256 _tokenId, address _from) internal {
        require(tokenId2UseOffer[_tokenId].owner != address(0), "Offer does not exist for this token.");
        require(isObjectReadyToUse(_tokenId), "Token already in another activity.");

        tokenId2UseStatus[_tokenId] = UseStatus({
            user: _from,
            owner: tokenId2UseOffer[_tokenId].owner,
            startTime: uint48(now),
            endTime : uint48(now) + tokenId2UseOffer[_tokenId].duration,
            price : tokenId2UseOffer[_tokenId].price,
            acceptedActivity : tokenId2UseOffer[_tokenId].acceptedActivity
            });

        delete tokenId2UseOffer[_tokenId];

        emit OfferTaken(_tokenId, _from, tokenId2UseStatus[_tokenId].owner, now, uint256(tokenId2UseStatus[_tokenId].endTime));

    }

    //TODO: allow batch operation
    function tokenFallback(address _from, uint256 _value, bytes _data) public {\
        uint256 tokenId;

        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize)
            tokenId := mload(add(ptr, 132))
        }

        uint256 expense = uint256(tokenId2UseOffer[tokenId].price);
        require(_value >= expense);

        tokenId2UseOffer[tokenId].owner.transfer(expense);

        _takeTokenUseOffer(tokenId, _from);
    }

    // start activity when token has no user at all
    function addActivity(
        uint256 _tokenId, address _user, uint256 _endTime
    ) public auth {
        // require the token user to verify even if it is from business logic.
        // if it is rent by others, can not addActivity by default.
        if(tokenId2UseStatus[_tokenId].user != address(0)) {
            require(_user == tokenId2UseStatus[_tokenId].user);
            require(
                tokenId2UseStatus[_tokenId].acceptedActivity == address(0) ||
                tokenId2UseStatus[_tokenId].acceptedActivity == msg.sender, "Token accepted activity is not accepted.");
        } else {
            require(
                address(0) == _user || ERC721(registry.addressOf(CONTRACT_OBJECT_OWNERSHIP)).ownerOf(_tokenId) == _user, "you can not use this token.");
        }

        require(tokenId2UseOffer[_tokenId].owner == address(0), "Can not start activity when offering.");

        require(IActivity(msg.sender).supportsInterface(0x6086e7f8), "Msg sender must be activity");

        require(isObjectReadyToUse(_tokenId), "Token should be available.");

        address activityObject = IInterstellarEncoder(registry.addressOf(CONTRACT_INTERSTELLAR_ENCODER)).getObjectAddress(_tokenId);
        IActivityObject(activityObject).activityAdded(_tokenId, msg.sender, _user);

        tokenId2CurrentActivity[_tokenId].activity = msg.sender;

        if(tokenId2UseStatus[_tokenId].endTime != 0) {
            tokenId2CurrentActivity[_tokenId].endTime = tokenId2UseStatus[_tokenId].endTime;
        } else {
            tokenId2CurrentActivity[_tokenId].endTime = uint48(_endTime);
        }


        emit ActivityAdded(_tokenId, msg.sender, uint48(tokenId2CurrentActivity[_tokenId].endTime));
    }

    function removeActivity(uint256 _tokenId, address _user) public auth {
                // require the token user to verify even if it is from business logic.
        // if it is rent by others, can not addActivity by default.
        if(tokenId2UseStatus[_tokenId].user != address(0)) {
            require(_user == tokenId2UseStatus[_tokenId].user);
        } else {
            require(
                address(0) == _user || ERC721(registry.addressOf(CONTRACT_OBJECT_OWNERSHIP)).ownerOf(_tokenId) == _user, "you can not use this token.");
        }
        
        require(tokenId2CurrentActivity[_tokenId].activity == msg.sender || msg.sender == address(this), "Must stop from current activity");

        address activityObject = IInterstellarEncoder(registry.addressOf(CONTRACT_INTERSTELLAR_ENCODER)).getObjectAddress(_tokenId);
        IActivityObject(activityObject).activityRemoved(_tokenId, msg.sender, _user);

        IActivity(tokenId2CurrentActivity[_tokenId].activity).activityStopped(_tokenId);

        delete tokenId2CurrentActivity[_tokenId];

        emit ActivityRemoved(_tokenId, msg.sender);
    }

    function removeTokenUseAndActivity(uint256 _tokenId) public {
        require(tokenId2UseStatus[_tokenId].user != address(0), "Object does not exist.");

        // when in activity, only user can stop
        if(isObjectInHireStage(_tokenId)) {
            require(tokenId2UseStatus[_tokenId].user == msg.sender);
        }

        _removeTokenUse(_tokenId);

        if (tokenId2CurrentActivity[_tokenId].activity != address(0)) {
            this.removeActivity(_tokenId, address(0));
        }
    }


    function _removeTokenUse(uint256 _tokenId) public {

        address owner = tokenId2UseStatus[_tokenId].owner;
        address user = tokenId2UseStatus[_tokenId].user;
        address activity = tokenId2CurrentActivity[_tokenId].activity;
        ERC721(registry.addressOf(CONTRACT_OBJECT_OWNERSHIP)).transferFrom(
            address(this), owner,  _tokenId);

        delete tokenId2UseStatus[_tokenId];
//        delete tokenId2CurrentActivity[_tokenId];

        emit TokenUseRemoved(_tokenId, owner, user, activity);
    }

    // for user-friendly
    function removeUseAndCreateOffer(uint256 _tokenId, uint256 _duration, uint256 _price, address _acceptedActivity) public {

        require(msg.sender == tokenId2UseStatus[_tokenId].owner);
        removeTokenUseAndActivity(_tokenId);

        tokenId2UseOffer[_tokenId] = UseOffer({
            owner: msg.sender,
            duration: uint48(_duration),
            price : _price,
            acceptedActivity: _acceptedActivity
            });

        emit OfferCreated(_tokenId, _duration, _price, _acceptedActivity, msg.sender);
    }

    function toBytes(address x) public pure returns (bytes b) {
        b = new bytes(32);
        assembly { mstore(add(b, 32), x) }
    }

}