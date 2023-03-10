// SPDX-License-Identifier: CC0-1.0

import "@openzeppelin/contracts/access/Ownable.sol";
import "./CosmicSignatureToken.sol";
import "./CosmicSignature.sol";
import "./RandomWalkNFT.sol";

pragma solidity ^0.8.19;

contract BiddingWar is Ownable {

    uint256 constant MILLION = 10**6;

    // how much the currentBid increases after every bid
    // we want 1%?
    uint256 public priceIncrease = 1010000; // we are going to divide this number by a million

    // how much the deadline is pushed after every bid
    uint256 public nanoSecondsExtra = 3600 * 10**9;

    // how much is the secondsExtra increased by after every bid (You can think of it as the second derivative)
    // 1.0001
    uint256 public timeIncrease = 1000100;

    // we need to set the bidPrice to anything higher than 0 because the
    // contract would break if it's zero and someone bids before a donation is made
    uint256 public bidPrice = 10**15;

    address public lastBidder = address(0);

    // Some money will go to charity
    address public charity;

    // 10% of the prize pool goes to the charity
    uint256 public charityPercentage = 10;

    // After a prize was claimed, start off the clock with this much time.
    uint256 public initialSecondsUntilPrize = 24 * 3600;

    // The bid size will be 1000 times smaller than the prize amount initially
    uint256 public initalBidAmountFraction = 1000;

    // You get 100 tokens when you bid
    uint256 public tokenReward = 100 * 1e18;

    uint256 public prizePercentage = 50;

    // when the money can be taken out
    uint256 public prizeTime;

    uint256 public numPrizes = 0;

    mapping(uint256 => bool) public usedRandomWalkNFTs;

    CosmicSignatureToken public token;
    CosmicSignature public nft;
    RandomWalkNFT public randomWalk;

    event PrizeClaimEvent(uint256 indexed prizeNum, address indexed destination, uint256 amount);
    event BidEvent(address indexed lastBidder, uint256 bidPrice, int256 randomWalkNFTID);
    event DonationEvent(address indexed donor, uint256 amount);

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    function getBidPrice() public view returns (uint256) {
        return (bidPrice * priceIncrease) / MILLION;
    }

    function initializeBidPrice() internal {
        bidPrice = prizeAmount() / initalBidAmountFraction;
    }

    // send some ETH into the contract and affect nothing else.
    function donate() public payable {
        require (msg.value > 0,"amount to donate must be greater than 0");

        if (lastBidder == address(0)) {
            initializeBidPrice();
        }

        emit DonationEvent(_msgSender(), msg.value);
    }

    function pushBackPrizeTime() internal {
        uint256 secondsAdded = nanoSecondsExtra / 1_000_000_000;
        prizeTime = max(prizeTime, block.timestamp) + secondsAdded;
        nanoSecondsExtra = (nanoSecondsExtra * timeIncrease) / MILLION;
    }

    function bidWithRWLK(uint256 randomWalkNFTID) public {
        // if you own a RandomWalkNFT, you can bid for free 1 time.
        // Each NFT can be used only once.
        if (lastBidder == address(0)) {
            // someone just claimed a prize and we are starting from scratch
            prizeTime = block.timestamp + initialSecondsUntilPrize;
        }

        lastBidder = _msgSender();

        require(!usedRandomWalkNFTs[randomWalkNFTID],"token with this ID was used already");
        require(randomWalk.ownerOf(randomWalkNFTID) == _msgSender(),"you must be the owner of the token");
        usedRandomWalkNFTs[randomWalkNFTID] = true;

        (bool mint_success, ) =
            address(token).call(abi.encodeWithSelector(CosmicSignatureToken.mint.selector, lastBidder,tokenReward));
		require(mint_success,"CosmicSignatureToken mint() failed to mint reward tokens");

        pushBackPrizeTime();

        emit BidEvent(lastBidder, bidPrice, int256(randomWalkNFTID));

    }

    function bid() public payable {

        if (lastBidder == address(0)) {
            // someone just claimed a prize and we are starting from scratch
            prizeTime = block.timestamp + initialSecondsUntilPrize;
        }

        lastBidder = _msgSender();

        uint256 newBidPrice = getBidPrice();

        require(
            msg.value >= newBidPrice,
            "The value submitted with this transaction is too low."
        );
        bidPrice = newBidPrice;

        (bool mint_success, ) =
            address(token).call(abi.encodeWithSelector(CosmicSignatureToken.mint.selector, lastBidder,tokenReward));
		require(mint_success,"CosmicSignatureToken mint() failed to mint reward tokens");

        pushBackPrizeTime();

        if (msg.value > bidPrice) {
            // Return the extra money to the bidder.
            (bool success, ) = lastBidder.call{value: msg.value - bidPrice}("");
            require(success, "Transfer failed.");
        }

        emit BidEvent(lastBidder, bidPrice, -1);
    }

    receive() external payable {
        bid();
    }

    function timeUntilPrize() public view returns (uint256) {
        if (prizeTime < block.timestamp) return 0;
        return prizeTime - block.timestamp;
    }

    function prizeAmount() public view returns (uint256) {
        return address(this).balance * prizePercentage / 100;
    }

    function charityAmount() public view returns (uint256) {
        return address(this).balance * charityPercentage / 100;
    }

    function claimPrize() public {
        require(_msgSender() == lastBidder, "Only last bidder can claim the prize.");
        require(timeUntilPrize() == 0, "Not enough time has elapsed.");

        address winner = lastBidder;
        lastBidder = address(0);

        numPrizes += 1;

        (bool mint_success, ) =
            address(nft).call(abi.encodeWithSelector(CosmicSignature.mint.selector, winner));
		require(mint_success,"CosmicSignature mint() failed to mint token");
        
        initializeBidPrice();

        uint256 prizeAmount_ = prizeAmount();
        uint256 charityAmount_ = charityAmount();

        (bool success, ) = winner.call{value: prizeAmount_}("");
        require(success, "Transfer failed.");

        (success, ) = charity.call{value: charityAmount_}("");
        require(success, "Transfer failed.");

        emit PrizeClaimEvent(numPrizes - 1, winner, prizeAmount_);
    }

    constructor() {
        charity = _msgSender();
    }

    function setCharity(address addr) public onlyOwner {
        charity = addr;
    }

    function setRandomWalk(address addr) public onlyOwner {
        randomWalk = RandomWalkNFT(addr);
    }

    function setCharityPercentage(uint256 newCharityPercentage) public onlyOwner {
        charityPercentage = newCharityPercentage;
    }

    function setTokenContract(address addr) public onlyOwner {
        token = CosmicSignatureToken(addr);
    }

    function setNftContract(address addr) public onlyOwner {
        nft = CosmicSignature(addr);
    }

    function setTimeIncrease(uint256 newTimeIncrease) public onlyOwner {
        timeIncrease = newTimeIncrease;
    }

    function setPriceIncrease(uint256 newPriceIncrease) public onlyOwner {
        priceIncrease = newPriceIncrease;
    }

    function setNanoSecondsExtra(uint256 newNanoSecondsExtra) public onlyOwner {
        nanoSecondsExtra = newNanoSecondsExtra;
    }

    function setInitialSecondsUntilPrize(uint256 newInitialSecondsUntilPrize) public onlyOwner {
        initialSecondsUntilPrize = newInitialSecondsUntilPrize;
    }

    function updatePrizePercentage(uint256 newPrizePercentage) public onlyOwner {
        prizePercentage = newPrizePercentage;
    }

    function updateInitalBidAmountFraction(uint256 newInitalBidAmountFraction) public onlyOwner {
        initalBidAmountFraction = newInitalBidAmountFraction;
    }

}
