pragma solidity ^0.4.21;
import "zeppelin-solidity/contracts/math/SafeMath.sol";
import "zeppelin-solidity/contracts/ownership/Claimable.sol";
import "zeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "zeppelin-solidity/contracts/access/Whitelist.sol";
import "../contracts/interface/TokenDealerInterface.sol";
import "./SeeleDividendsToEth.sol";
import "./S3Devents.sol";

contract SeeleDealer is Claimable, Whitelist, S3DEvents{ 

    /*=================================
    =            MODIFIERS            =
    =================================*/
    // only people with tokens
    modifier onlyBagholders(address myAddress) {
        require(balanceOf(myAddress) > 0);
        _;
    }
    
    // only people with profits
    modifier onlyStronghands(address myAddress) {
        require(myDividends(myAddress, true) > 0);
        _;
    }
    
 
    // ensures that the first tokens in the contract will be equally distributed
    // meaning, no divine dump will be ever possible
    // result: healthy longevity.
    modifier antiEarlyWhale(address buyer, uint256 _amountOfEthereum){
        address _customerAddress = buyer;
        
        // are we still in the vulnerable phase?
        // if so, enact anti early whale protocol 
        if( onlyAmbassadors && ((totalBalance() - _amountOfEthereum) <= ambassadorQuota_ )){
            require(
                // is the customer in the ambassador list?
                ambassadors_[_customerAddress] == true &&
                
                // does the customer purchase exceed the max ambassador quota?
                (ambassadorAccumulatedQuota_[_customerAddress] + _amountOfEthereum) <= ambassadorMaxPurchase_
                
            );
            
            // updated the accumulated quota    
            ambassadorAccumulatedQuota_[_customerAddress] = SafeMath.add(ambassadorAccumulatedQuota_[_customerAddress], _amountOfEthereum);
        
            // execute
            _;
        } else {
            // in case the ether count drops low, the ambassador phase won't reinitiate
            onlyAmbassadors = false;
            _;    
        }
        
    }
    
    /*=====================================
    =            CONFIGURABLES            =
    =====================================*/
    string public name = "Seele-S3D";
    string public symbol = "Seele-S3D";
    uint8 constant public decimals = 18;
    uint8 constant internal dividendFee_ = 10;
    uint8 internal ethDividendFee_ = 50;

    uint256 constant internal tokenPriceInitial_ = 0.0010356 * 1e18;
    uint256 constant internal tokenPriceIncremental_ = 0.00010356 * 1e18;
    uint256 constant internal magnitude = 2**64;
    
    // proof of stake (defaults at 100 tokens)
    uint256 public stakingRequirement = 100e18;
    
    // ambassador program
    mapping(address => bool) internal ambassadors_;
    uint256 constant internal ambassadorMaxPurchase_ = 10000;
    uint256 constant internal ambassadorQuota_ = 200000;
    
    address public seeleTokenAddress = 0x47879ac781938CFfd879392Cd2164b9F7306188a;
   /*================================
    =            DATASETS            =
    ================================*/
    // amount of shares for each address (scaled number)
    mapping(address => uint256) internal tokenBalanceLedger_;
    mapping(address => uint256) internal referralBalance_;
    mapping(address => int256) internal payoutsTo_;
    mapping(address => uint256) internal ambassadorAccumulatedQuota_;

    mapping(address => uint256) public escapeTokenBalance_;
    mapping(address => uint256) public overSellTokenBalance_;

    uint256 internal tokenSupply_ = 0;
    uint256 internal profitPerShare_;

    //NEED DO!! change to internal
    uint256 public escapeTokenSuppley_ = 0;
    uint256 public overSellTokenAmount_ = 0;
    
 
    // when this is set to true, only ambassadors can purchase tokens (this prevents a whale premine, it ensures a fairly distributed upper pyramid)
    bool public onlyAmbassadors = true;

    address public seeleDividendsToEthContractAddress = 0x47879ac781938CFfd879392Cd2164b9F7306188a;
    /*=======================================
    =            PUBLIC FUNCTIONS            =
    =======================================*/
    /*
    * -- APPLICATION ENTRY POINTS --  
    */
    function SeeleDealer(address tokenAddress)
        public
    {
        seeleTokenAddress = tokenAddress;

        // add the ambassadors here.
        // mantso - lead solidity dev & lead web dev. 
        ambassadors_[0xCd16575A90eD9506BCf44C78845d93F1b647F48C] = true;
    }
    
    function setSeeleDividendsToEthContractAddress(address dividendsAddress)
        public 
        onlyOwner()
    {
        seeleDividendsToEthContractAddress = dividendsAddress;
    }

    /**
     * Converts all incoming ethereum to tokens for the caller, and passes down the referral addy (if any)
     */
    function buy(address buyer, uint256 seeleAmount, address _referredBy)
        public
        payable
        onlyIfWhitelisted(msg.sender)
        returns(uint256)
    {
        //transfer seele to contract
        require(ERC20(seeleTokenAddress).transferFrom(buyer, address(this), seeleAmount));
        purchaseTokens(buyer, seeleAmount, _referredBy);
    }
    
    /*
     * default fallback函数
    */
    function()
        payable
        public
    {
        
    }

    /**
     * Converts all of caller's dividends to tokens.
     */
    function reinvest(address buyer, uint buyAmount)
        onlyStronghands(buyer)
        onlyIfWhitelisted(msg.sender)
        public
    {
        // fetch dividends
        uint256 _dividends = myDividends(buyer, false); // retrieve ref. bonus later in the code
        uint256 _referralBalance = referralBalance_[buyer];
        require(buyAmount <= (_dividends + _referralBalance));

        if (buyAmount <= _dividends) {
            // pay out the dividends virtually
            payoutsTo_[buyer] +=  (int256)(buyAmount * magnitude);
        } else {
            payoutsTo_[buyer] +=  (int256) (_dividends * magnitude);
            // retrieve ref. bonus
            referralBalance_[buyer] = SafeMath.sub(referralBalance_[buyer], buyAmount - _dividends);
        }
                
        // dispatch a buy order with the virtualized "withdrawn dividends"
        uint256 _tokens = purchaseTokens(buyer, buyAmount, 0x0);
        
        // fire event
        emit S3DEvents.onReinvestment(buyer, buyAmount, _tokens);
    }

    // function reinvest(address buyer)
    //     onlyStronghands(buyer)
    //     public
    // {
    //     // fetch dividends
    //     uint256 _dividends = myDividends(buyer, false); // retrieve ref. bonus later in the code
        
    //     // pay out the dividends virtually
    //     address _customerAddress = buyer;
    //     payoutsTo_[_customerAddress] +=  (int256) (_dividends * magnitude);
        
    //     // retrieve ref. bonus
    //     _dividends += referralBalance_[_customerAddress];
    //     referralBalance_[_customerAddress] = 0;
        
    //     // dispatch a buy order with the virtualized "withdrawn dividends"
    //     uint256 _tokens = purchaseTokens(_customerAddress, _dividends, 0x0);
        
    //     // fire event
    //     emit onReinvestment(_customerAddress, _dividends, _tokens);
    // }
    
    /**
     * Alias of sell() and withdraw().
     */
    function exit(address buyer)
        onlyIfWhitelisted(msg.sender)
        public
    {
        // get token count for caller & sell them all
        address _customerAddress = buyer;
        uint256 _tokens = tokenBalanceLedger_[_customerAddress];
        if(_tokens > 0) 
            sell(buyer, _tokens);
        
        // lambo delivery service
        withdraw(buyer);
    }

    /**
     * Withdraws all of the callers earnings.
     */
    function withdraw(address buyer)
        onlyStronghands(buyer)
        onlyIfWhitelisted(msg.sender)
        public
    {
        // setup data
        address _customerAddress = buyer;
        uint256 _dividends = myDividends(_customerAddress, false); // get ref. bonus later in the code
        
        // update dividend tracker
        payoutsTo_[_customerAddress] +=  (int256) (_dividends * magnitude);
        
        // add ref. bonus
        _dividends += referralBalance_[_customerAddress];
        referralBalance_[_customerAddress] = 0;
        
        // lambo delivery service
        //_customerAddress.transfer(_dividends);
        ERC20(seeleTokenAddress).transfer(_customerAddress, _dividends);
        
        // fire event
        emit S3DEvents.onWithdraw(_customerAddress, _dividends);
    }

    function withdraw(address buyer, uint256 withdrawAmount)
        onlyStronghands(buyer)
        onlyIfWhitelisted(msg.sender)
        public
    {
        // setup data
        uint256 _dividends = myDividends(buyer, false); // get ref. bonus later in the code
        uint256 _referralBalance = referralBalance_[buyer];
        require(withdrawAmount <= (_dividends + _referralBalance));

        if (withdrawAmount <= _dividends) {
            // pay out the dividends virtually
            payoutsTo_[buyer] +=  (int256)(withdrawAmount * magnitude);
        } else {
            // retrieve ref. bonus
            payoutsTo_[buyer] +=  (int256) (_dividends * magnitude);
            referralBalance_[buyer] = SafeMath.sub(referralBalance_[buyer], withdrawAmount - _dividends);
        }
        
        
        // lambo delivery service
        //_customerAddress.transfer(withdrawAmount);
        ERC20(seeleTokenAddress).transfer(buyer, _dividends);
        
        // fire event
        emit S3DEvents.onWithdraw(buyer, withdrawAmount);
    }
    
    /**
     * Liquifies tokens to ethereum.
     */
    function sell(address seller, uint256 _amountOfTokens)
        onlyBagholders(seller)
        onlyIfWhitelisted(msg.sender)
        public
    {
        // setup data
        address _customerAddress = seller;
        // russian hackers BTFO
        require(_amountOfTokens <= tokenBalanceLedger_[_customerAddress]);
        uint256 _tokens = _amountOfTokens;
        uint256 _seeleAmount = tokensToSeele(_tokens);
        uint256 _dividends = SafeMath.div(_seeleAmount, dividendFee_);
        _dividends = splitDividendsToEth(_dividends);
        uint256 _taxedSeele = SafeMath.sub(_seeleAmount, _dividends);
        
        // burn the sold tokens
        tokenSupply_ = SafeMath.sub(tokenSupply_, _tokens);
        tokenBalanceLedger_[_customerAddress] = SafeMath.sub(tokenBalanceLedger_[_customerAddress], _tokens);
        
        // update dividends tracker
        int256 _updatedPayouts = (int256) (profitPerShare_ * _tokens + (_taxedSeele * magnitude));
        payoutsTo_[_customerAddress] -= _updatedPayouts;       
        
        // dividing by zero is a bad idea
        uint256 dividendTokenAmount_ =  getDividendTokenAmount();
        if (dividendTokenAmount_ > 0) {
            // update the amount of dividends per token
            profitPerShare_ = SafeMath.add(profitPerShare_, (_dividends * magnitude) / dividendTokenAmount_);
        }
        
        // fire event
        emit S3DEvents.onTokenSell(_customerAddress, _tokens, _taxedSeele);
    }
    
    /**
     * Transfer tokens from the caller to a new holder.
     * Remember, there's a 10% fee here as well.
     */
    // function transfer(address _toAddress, uint256 _amountOfTokens)
    //     onlyBagholders()
    //     public
    //     returns(bool)
    // {
    //     // setup
    //     address _customerAddress = msg.sender;
        
    //     // make sure we have the requested tokens
    //     // also disables transfers until ambassador phase is over
    //     // ( we dont want whale premines )
    //     require(!onlyAmbassadors && _amountOfTokens <= tokenBalanceLedger_[_customerAddress]);
        
    //     // withdraw all outstanding dividends first
    //     if(myDividends(true) > 0) withdraw();
        
    //     // liquify 10% of the tokens that are transfered
    //     // these are dispersed to shareholders
    //     uint256 _tokenFee = SafeMath.div(_amountOfTokens, dividendFee_);
    //     uint256 _taxedTokens = SafeMath.sub(_amountOfTokens, _tokenFee);
    //     uint256 _dividends = tokensToSeele(_tokenFee);
  
    //     // burn the fee tokens
    //     tokenSupply_ = SafeMath.sub(tokenSupply_, _tokenFee);

    //     // exchange tokens
    //     tokenBalanceLedger_[_customerAddress] = SafeMath.sub(tokenBalanceLedger_[_customerAddress], _amountOfTokens);
    //     tokenBalanceLedger_[_toAddress] = SafeMath.add(tokenBalanceLedger_[_toAddress], _taxedTokens);
        
    //     // update dividend trackers
    //     payoutsTo_[_customerAddress] -= (int256) (profitPerShare_ * _amountOfTokens);
    //     payoutsTo_[_toAddress] += (int256) (profitPerShare_ * _taxedTokens);
        
    //     // disperse dividends among holders
    //     profitPerShare_ = SafeMath.add(profitPerShare_, (_dividends * magnitude) / tokenSupply_);
        
    //     // fire event
    //     emit Transfer(_customerAddress, _toAddress, _taxedTokens);
        
    //     // ERC20
    //     return true;
       
    // }
    
    /*----------  ADMINISTRATOR ONLY FUNCTIONS  ----------*/
    /**
     * In case the amassador quota is not met, the administrator can manually disable the ambassador phase.
     */
    function disableInitialStage()
        onlyOwner()
        public
    {
        onlyAmbassadors = false;
    }
    
    /**
     * Precautionary measures in case we need to adjust the masternode rate.
     */
    // function setStakingRequirement(uint256 _amountOfTokens)
    //     onlyOwner()
    //     public
    // {
    //     stakingRequirement = _amountOfTokens;
    // }
    
    /**
     * If we want to rebrand, we can.
     */
    function setName(string _name)
        onlyOwner()
        public
    {
        name = _name;
    }
    
    /**
     * If we want to rebrand, we can.
     */
    function setSymbol(string _symbol)
        onlyOwner()
        public
    {
        symbol = _symbol;
    }

    
    /*----------  HELPERS AND CALCULATORS  ----------*/
    /**
     * Method to view the current Ethereum stored in the contract
     * Example: totalEthereumBalance()
     */
    function totalBalance()
        public
        view
        returns(uint256)
    {
        return ERC20(seeleTokenAddress).balanceOf(address(this));
    }
    
    /**
     * Retrieve the total token supply.
     */
    function totalSupply()
        public
        view
        returns(uint256)
    {
        return tokenSupply_;
    }
    
    
    /**
     * Retrieve the dividends owned by the caller.
     * If `_includeReferralBonus` is to to 1/true, the referral bonus will be included in the calculations.
     * The reason for this, is that in the frontend, we will want to get the total divs (global + ref)
     * But in the internal calculations, we want them separate. 
     */ 
    function myDividends(address myAddress, bool _includeReferralBonus) 
        public 
        view 
        returns(uint256)
    {
        address _customerAddress = myAddress;
        return _includeReferralBonus ? dividendsOf(_customerAddress) + referralBalance_[_customerAddress] : dividendsOf(_customerAddress) ;
    }
    
    /**
     * Retrieve the token balance of any single address.
     */
    function balanceOf(address _customerAddress)
        view
        public
        returns(uint256)
    {
        return tokenBalanceLedger_[_customerAddress];
    }
    
    /**
     * Retrieve the dividend balance of any single address.
     */
    function dividendsOf(address _customerAddress)
        view
        public
        returns(uint256)
    {
        return (uint256) ((int256)(profitPerShare_ * tokenBalanceLedger_[_customerAddress]) - payoutsTo_[_customerAddress]) / magnitude;
    }
    
    function referralBalanceOf(address _customerAddress)
        view
        public 
        returns(uint256)
    {
        return referralBalance_[_customerAddress];
    }

    /**
     * Return the buy price of 1 individual token.
     */
    function sellPrice() 
        public 
        view 
        returns(uint256)
    {
        // our calculation relies on the token supply, so we need supply. Doh.
        if(getPricedTokenAmount() == 0){
            return tokenPriceInitial_ - tokenPriceIncremental_;
        } else {
            uint256 _seeleAmount = tokensToSeele(1e18);
            uint256 _dividends = SafeMath.div(_seeleAmount, dividendFee_  );
            uint256 _taxedSeele = SafeMath.sub(_seeleAmount, _dividends);
            return _taxedSeele;
        }
    }
    
    /**
     * Return the sell price of 1 individual token.
     */
    function buyPrice() 
        public 
        view 
        returns(uint256)
    {
        // our calculation relies on the token supply, so we need supply. Doh.
        if(getPricedTokenAmount() == 0){
            return tokenPriceInitial_ + tokenPriceIncremental_;
        } else {
            uint256 _seeleAmount = tokensToSeele(1e18);
            uint256 _dividends = SafeMath.div(_seeleAmount, dividendFee_  );
            uint256 _taxedSeele = SafeMath.add(_seeleAmount, _dividends);
            return _taxedSeele;
        }
    }
    
    /**
     * Function for the frontend to dynamically retrieve the price scaling of buy orders.
     */
    function calculateTokensReceived(uint256 _seeleToSpend) 
        public 
        view 
        returns(uint256)
    {
        uint256 _dividends = SafeMath.div(_seeleToSpend, dividendFee_);
        uint256 _taxedSeele = SafeMath.sub(_seeleToSpend, _dividends);
        uint256 _amountOfTokens = seeleToTokens_(_taxedSeele);
        
        return _amountOfTokens;
    }
    
    function calculateBuyTokenSpend(uint256 _tokensToBuy)
        public 
        view
        returns(uint256)
    {
        uint256 _seeleAmount = tokensToSeele(_tokensToBuy);
        uint256 _dividends = SafeMath.div(_seeleAmount, dividendFee_);
        uint256 _taxedSeele = SafeMath.sub(_seeleAmount, _dividends);
        return _taxedSeele;
    }

    /**
     * Function for the frontend to dynamically retrieve the price scaling of sell orders.
     */
    function calculateBuyTokenReceived(uint256 _tokensToSell) 
        public 
        view 
        returns(uint256)
    {
        require(_tokensToSell <= getPricedTokenAmount());
        uint256 _seeleAmount = tokensToSeele(_tokensToSell);
        uint256 _dividends = SafeMath.div(_seeleAmount, dividendFee_);
        uint256 _taxedSeele = SafeMath.sub(_seeleAmount, _dividends);
        return _taxedSeele;
    }
    
    function setEthDividendFee(uint8 ethDividendFee)
        public
        onlyOwner()
    {
        ethDividendFee_ = ethDividendFee;
    }

    function splitDividendsToEth(uint256 _undividedDividends)
        internal 
        view
        returns (uint256)
    {
        if (ethDividendFee_ > 0) {
            uint256 _ethDividends = SafeMath.div(_undividedDividends, ethDividendFee_);
            uint restDividends = SafeMath.sub(_undividedDividends, _ethDividends);  
            ERC20(seeleTokenAddress).transfer(seeleDividendsToEthContractAddress, _ethDividends);  
            SeeleDividendsToEth(seeleDividendsToEthContractAddress).AddDividends(_ethDividends);
            return restDividends;
        } else {
            return _undividedDividends;
        }
    }

    /*==========================================
    =            INTERNAL FUNCTIONS            =
    ==========================================*/
    function purchaseTokens(address buyer, uint256 _incomingSeele, address _referredBy)
        antiEarlyWhale(buyer, _incomingSeele)
        internal
        returns(uint256)
    {
        // data setup
        //address _customerAddress = buyer;
        uint256 _undividedDividends = SafeMath.div(_incomingSeele, dividendFee_);
        _undividedDividends = splitDividendsToEth(_undividedDividends);
        uint256 _referralBonus = SafeMath.div(_undividedDividends, 3);
        uint256 _dividends = SafeMath.sub(_undividedDividends, _referralBonus);
        uint256 _taxedSeele = SafeMath.sub(_incomingSeele, _undividedDividends);
        uint256 _amountOfTokens = seeleToTokens_(_taxedSeele);
        uint256 _fee = _dividends * magnitude;
 
        // no point in continuing execution if OP is a poorfag russian hacker
        // prevents overflow in the case that the pyramid somehow magically starts being used by everyone in the world
        // (or hackers)
        // and yes we know that the safemath function automatically rules out the "greater then" equasion.
        require(_amountOfTokens > 0 && (SafeMath.add(_amountOfTokens,tokenSupply_) > tokenSupply_));
        
        // is the user referred by a masternode?
        if(
            // is this a referred purchase?
            _referredBy != 0x0000000000000000000000000000000000000000 &&

            // no cheating!
            _referredBy != buyer
            
            // does the referrer have at least X whole tokens?
            // i.e is the referrer a godly chad masternode
            //tokenBalanceLedger_[_referredBy] >= stakingRequirement
        ){
            // wealth redistribution
            referralBalance_[_referredBy] = SafeMath.add(referralBalance_[_referredBy], _referralBonus);
        } else {
            // no ref purchase
            // add the referral bonus back to the global dividends cake
            _dividends = SafeMath.add(_dividends, _referralBonus);
            _fee = _dividends * magnitude;
        }
        
        // we can't give people infinite ethereum
        if(tokenSupply_ > 0){
            
            // add tokens to the pool
            tokenSupply_ = SafeMath.add(tokenSupply_, _amountOfTokens);

            //uint256 dividendTokenAmount_ =  getDividendTokenAmount();
 
            // take the amount of dividends gained through this transaction, and allocates them evenly to each shareholder
            profitPerShare_ += (_dividends * magnitude / (getDividendTokenAmount()));
            
            // calculate the amount of tokens the customer receives over his purchase 
            _fee = _fee - (_fee-(_amountOfTokens * (_dividends * magnitude / (getDividendTokenAmount()))));
        
        } else {
            // add tokens to the pool
            tokenSupply_ = _amountOfTokens;
        }
        
        // update circulating supply & the ledger address for the customer
        tokenBalanceLedger_[buyer] = SafeMath.add(tokenBalanceLedger_[buyer], _amountOfTokens);
        
        // Tells the contract that the buyer doesn't deserve dividends for the tokens before they owned them;
        //really i know you think you do but you don't

        //int256 _updatedPayouts = (int256) ((profitPerShare_ * _amountOfTokens) - _fee);
        payoutsTo_[buyer] += (int256) ((profitPerShare_ * _amountOfTokens) - _fee);
        
        // fire event
        emit S3DEvents.onTokenPurchase(buyer, _incomingSeele, _amountOfTokens, _referredBy);
        
        return _amountOfTokens;
    }

    /**
     * Calculate Token price based on an amount of incoming ethereum
     * It's an algorithm, hopefully we gave you the whitepaper with it in scientific notation;
     * Some conversions occurred to prevent decimal errors or underflows / overflows in solidity code.
     */
    function seeleToTokens_(uint256 seeleAmount)
        internal
        view
        returns(uint256)
    {
        uint256 _tokenPriceInitial = tokenPriceInitial_ ;
        uint256 _tokenSupply =  getPricedTokenAmount();
        uint256 _tokensReceived = 
         (
            (
                // underflow attempts BTFO
                SafeMath.sub(
                    (sqrt
                        (
                            (_tokenPriceInitial**2)
                            +
                            (2*(tokenPriceIncremental_ * 1e18 )*(seeleAmount * 1e18))
                            +
                            (((tokenPriceIncremental_)**2)*(tokenSupply_**2))
                            +
                            (2*(tokenPriceIncremental_)*_tokenPriceInitial*tokenSupply_)
                        )
                    ), _tokenPriceInitial
                )
            )/(tokenPriceIncremental_)
        )-(tokenSupply_)
        ;
  
        return _tokensReceived;
    }
    
    /**
     * Calculate token sell value.
     * It's an algorithm, hopefully we gave you the whitepaper with it in scientific notation;
     * Some conversions occurred to prevent decimal errors or underflows / overflows in solidity code.
     */
     function tokensToSeele(uint256 _tokens)
        internal
        view
        returns(uint256)
    {

        uint256 tokens_ = (_tokens + 1e18);
        uint256 _tokenSupply = (getPricedTokenAmount() + 1e18);
        uint256 _seeleReceived =
        (
            // underflow attempts BTFO
            SafeMath.sub(
                (
                    (
                        (
                            tokenPriceInitial_ +(tokenPriceIncremental_ * (_tokenSupply/1e18))
                        )-tokenPriceIncremental_
                    )*(tokens_ - 1e18)
                ),(tokenPriceIncremental_*((tokens_**2-tokens_)/1e18))/2
            )
        /1e18);
        return _seeleReceived;
    }
    
    
    //This is where all your gas goes, sorry
    //Not sorry, you probably only paid 1 gwei
    function sqrt(uint x) internal pure returns (uint y) {
        uint z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    //不用给套利的token分红
    function getDividendTokenAmount() internal view returns (uint256) {
        //exclude escape token
        //return SafeMath.sub(tokenSupply_ , escapeTokenSuppley_);
        return tokenSupply_;
    }

    //计价的token要排除oversell的token
    function getPricedTokenAmount() internal view returns (uint256) {
        return SafeMath.sub(SafeMath.add(tokenSupply_, escapeTokenSuppley_), overSellTokenAmount_);
    }

    //NEW FUNCTION        
    function escapeTokens(address sellerAddress, uint256 _amountOfTokens) 
        onlyBagholders(sellerAddress) 
        onlyIfWhitelisted(msg.sender)
        public 
        returns(uint256)
    {
        // setup data
        address _customerAddress = sellerAddress;

        // russian hackers BTFO
        require(_amountOfTokens <= tokenBalanceLedger_[_customerAddress]);
        uint256 _tokens = _amountOfTokens;

        // add the sold tokens to escape tokens
        tokenSupply_ = SafeMath.sub(tokenSupply_, _tokens);
        escapeTokenSuppley_ = SafeMath.add(escapeTokenSuppley_, _tokens);
        tokenBalanceLedger_[_customerAddress] = SafeMath.sub(tokenBalanceLedger_[_customerAddress], _tokens);
        escapeTokenBalance_[_customerAddress] = SafeMath.add(escapeTokenBalance_[_customerAddress], _tokens);
   
        // update dividends tracker
        // take you token dividends
        int256 _updatedPayouts = (int256) (profitPerShare_ * _tokens);
        payoutsTo_[_customerAddress] -= _updatedPayouts;       

        // fire event
        emit S3DEvents.onTokenEscape(_customerAddress, _tokens);
        return _tokens;
    }

    //套利
    function arbitrageTokens(address sellerAddress,  uint256 _amountOfTokens) 
        onlyIfWhitelisted(msg.sender)
        public
    {
        require(_amountOfTokens <= getPricedTokenAmount());
        
        // setup data
        address _customerAddress = sellerAddress;
        
        // TokenDealerInterface escapeContract = TokenDealerInterface(sellTokenAddress);
        // uint256 _tokens = escapeContract.escapeTokens(_customerAddress, _amountOfTokens);
        // require(_tokens == _amountOfTokens);

        // russian hackers BTFO
        uint256 _seeleAmount = tokensToSeele(_amountOfTokens);
        require(_seeleAmount <= totalBalance());        

        uint256 _dividends = SafeMath.div(_seeleAmount, dividendFee_);
        uint256 _taxedSeele = SafeMath.sub(_seeleAmount, _dividends);
        
        // burn the sold tokens
        //tokenSupply_ = SafeMath.sub(tokenSupply_, _tokens);
        //tokenBalanceLedger_[_customerAddress] = SafeMath.sub(tokenBalanceLedger_[_customerAddress], _tokens);

        // add escape tokens to oversell
        overSellTokenAmount_ = SafeMath.add(overSellTokenAmount_, _amountOfTokens);
        overSellTokenBalance_[_customerAddress] = SafeMath.add(overSellTokenBalance_[_customerAddress], _amountOfTokens);

             
        // dividing by zero is a bad idea
        uint256 dividendTokenAmount_ =  getDividendTokenAmount();
        if (dividendTokenAmount_ > 0) {
            // update the amount of dividends per token
            profitPerShare_ = SafeMath.add(profitPerShare_, (_dividends * magnitude) / dividendTokenAmount_);
        }
        
        // lambo delivery service
        //_customerAddress.transfer(_taxedEthereum);
        ERC20(seeleTokenAddress).transfer(_customerAddress, _taxedSeele);

        // fire event
        emit S3DEvents.onTokenArbitrage(_customerAddress, _amountOfTokens, _taxedSeele);
    }
}