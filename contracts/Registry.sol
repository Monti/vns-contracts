pragma solidity ^0.5.2;

import "openzeppelin-solidity/contracts/token/ERC721/ERC721Full.sol";
import "openzeppelin-solidity/contracts/drafts/Counters.sol";
import "./utils/StringLength.sol";

// Notes:
// * All domains must be lower case, this will be done by enforcing 0-9, a-z

contract Registry is ERC721Full {
    // using Counters for Counters.Counter;
    using StringLength for string;
    
    constructor() ERC721Full("VeChain Name Service", "VNS") public {
        _tokenCount.increment();                            // Start counters at 1
        _auctionCount.increment();                          // Start counters at 1
    }

    struct Auction {
        uint                    winningBid;
        address                 winningBidder;
        uint                    auctionEnd;
        string                  domainName;
        bool                    biddingEnded;
        uint                    revealEnd;
        mapping(address => uint)   refunds;                 // Mapping from address to refund amount
        mapping(address => bytes32) blindedBid;             // Mapping from id to shielded bids - sending a new bid updates your bid
    }

    Counters.Counter private _tokenCount;
    Counters.Counter private _auctionCount;

    // Mapping from token to domain name
    mapping(uint256 => string) private _tokenToDomain;

    // Mapping from domain to address
    mapping(string => address) private _domainToAddress;

    // Mapping from domain to subdomain
    mapping(string => string) private _subDomainToDomain;

    // Mapping from subdomain to address
    mapping(string => address) private _subDomainToAddress;

    // Mapping from auction ID to auction struct
    mapping(uint256 => Auction) private _auctions;

    // Mapping from domain names to active auction status.
    mapping(string => uint256) private _domainToAuction;

    // Mapping from tokenIDs to purchase cost
    mapping(uint256 => uint256) private _tokenToCost;

    // Mapping from tokenIDs to purchase cost
    mapping(address => uint256[]) private _userAuctions;


    // View Functions
    // Domain
    function resolveDomain(string calldata _domainName) external view returns (address) {
        return _domainToAddress[_domainName];
    }

    function getAuctionEnd(uint256 _auctionID) external view returns (uint256) {
        return _auctions[_auctionID].auctionEnd;
    }

    // Auction
    function getUserAuctions(address _user) external view returns (uint256[] memory auctions) {
        return _userAuctions[_user];
    }


    // External Public Functions
    // Domain Functions
    function addSubdomain(uint256 _tokenID, string calldata _subDomain, address _targetAddress) external {
        _isApprovedOrOwner(msg.sender, _tokenID);

        string memory _domain = _tokenToDomain[_tokenID];
        _subDomainToDomain[string(abi.encodePacked(_subDomain, ".", _domain))] = _domain;
        _subDomainToAddress[string(abi.encodePacked(_subDomain, ".", _domain))] = _targetAddress;
    }

    function removeSubdomain(uint256 _tokenID, string calldata _subDomain) external {
        _isApprovedOrOwner(msg.sender, _tokenID);

        string memory _domain = _tokenToDomain[_tokenID];
        _subDomainToDomain[string(abi.encodePacked(_subDomain, ".", _domain))] = "";
        _subDomainToAddress[string(abi.encodePacked(_subDomain, ".", _domain))] = address(0);
    }
    
    function invalidateDomain(uint256 _tokenID) external {                          // Lets users delete domains that are > 6 chars
        string memory domainName =  _tokenToDomain[_tokenID];
        require(StringLength.strlen(domainName) < 7);                               // Minimum size is 6, longer domains will be deleted

        _burnDomain(_tokenID, domainName);                                          // Wipe domain data and delete the token
    }

    // Auction Functions
    function startAuction(string calldata _domain) external payable returns (uint256 id) {
        return _newAuction(_domain);
    }

    function bidOnAuction(uint256 _auctionID, bytes32 _blindedBid) external payable {       // !!! CHECK IF THIS IS RE-ENTERABLE !!!
        Auction storage a = _auctions[_auctionID];
        
        require(
            now < a.auctionEnd && !a.biddingEnded,
            "Cannot bid after auction has ended"
        );

        require(
            msg.value == 10 ether,                                          // Bond dissincentivises no-show bidding
            "Bidder must attach a good behaviour bond"
        );

        _userAuctions[msg.sender].push(_auctionID);                                   // Let the user find the a

        if (a.blindedBid[msg.sender] == "") {                               // If user doesn't already have a bid
            a.blindedBid[msg.sender] = _blindedBid;
            return;
        } else {
            a.blindedBid[msg.sender] = _blindedBid;
            msg.sender.transfer(10 ether);                                  // Refund their 2nd behaviour bond !!! CHECK IF THIS IS RE-ENTERABLE !!!
        }
    }

    function finalizeBidding(uint256 _auctionID) external {
        Auction storage a = _auctions[_auctionID];
        
        require(
            now > a.auctionEnd && !a.biddingEnded,
            "Cannot close an auction too early, or after it has already been closed"
        );

        a.biddingEnded == true;
        a.revealEnd = now + 1 days;
        // Emit auctionEnd event
    }

    function revealBid(bytes32 _secret, uint256 _auctionID) external payable returns (bool winning) {
        Auction storage a = _auctions[_auctionID];
        
        require(
            !a.biddingEnded && now < a.revealEnd,
            "Cannot reveal before auction has ended and after reveal period has ended"
        );

        require(
            a.blindedBid[msg.sender] == keccak256(abi.encodePacked(msg.value, _secret)),
            "Secret or attached value were incorrect"
        );

        if (msg.value <= a.winningBid) {
            delete(a.blindedBid[msg.sender]);
            msg.sender.transfer(msg.value + 10);
            return false;
        }

        if (a.winningBidder != address(0)) {
            a.refunds[a.winningBidder] += a.winningBid + 10 ether; // Can we implicitly convert ether to uint256?
        }

        a.winningBidder = msg.sender;
        a.winningBid = msg.value;
        return true;
    }

    function finalizeAuction(uint256 _auctionID) external {
        Auction storage a = _auctions[_auctionID];
        
        require(
            now > a.revealEnd,
            "Cannot finalize the auction too early"
        );
        
        _registerDomain(a.domainName, a.winningBidder, a.winningBid);   // Winning bidder receives the domain
        delete(_auctions[_auctionID]);                                  // Delete the auction struct
        // Emit auctionEnd event
    }

    // Private Functions
    function _registerDomain(string memory _domainName, address _owner, uint256 _pricePaid) internal {
        require(
            verifyNewDomain(_domainName),
            "Domain is already registered"
        );          

        uint256 _tokenID = _tokenCount.current();                       // tokenID is equal to its count
        _mint(_owner, _tokenID);                                        // Call the mint function of ERC721Enumerable
        _tokenCount.increment();                                        // Increment counter after minting

        // Set VNS Specific Data
        _tokenToDomain[_tokenID] = _domainName;                         // Link the tokenID to the current address
        _domainToAddress[_domainName] = _owner;                         // Intialize the address to point at the owner
        _tokenToCost[_tokenID] = _pricePaid;                            // Record how much the domain cost to register
        delete(_domainToAuction[_domainName]);                          // Stop blocking new auctions for this domain (should it deregister)
    }

    function _newAuction(string memory _domain) internal returns (uint256) {
        require(
            verifyNewDomain(_domain),
            "Can't register an already existing domain"
        );
        require(
            _domainToAuction[_domain] == 0,
            "There is already an active auction for this domain"
        );

        uint _auctionID = _auctionCount.current();
        uint _auctionEnd = now + 3 days;                        // Bidding lasts 3 days
        _auctions[_auctionID] = Auction(0, address(0), _auctionEnd, _domain, false, 0);   // Creates new auction struct in the auctions mapping
        _domainToAuction[_domain] = _auctionID;

        _auctionCount.increment();
        return _auctionID;
    }

    // Helper Functions
    function verifyNewDomain(string memory _domainName) internal view returns (bool) {
        return _domainToAddress[_domainName] == address(0);
    }

    function _burnDomain(uint256 _tokenID, string memory _domainName) internal {
        delete _tokenToDomain[_tokenID];
        delete _domainToAddress[_domainName];
        _burn(ownerOf(_tokenID), _tokenID);
    }

}