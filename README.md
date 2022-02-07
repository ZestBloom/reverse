![Reverse](https://user-images.githubusercontent.com/23183451/152804580-87566611-7322-4025-9e52-282c7849dd6a.png)

# Reverse

Reverse is a reach app, similar to auction, in which an ASA holder to auction an asset for ALGOs. It allows buying and price discovery on the asset during the auction. After the end of the auction time the contract can be closed out resulting in payouts to the seller, marketplace, creator and a transfer of the asset to the buyer. Reverse auctions begin at some start price and work down to a floor price.

## Activation

0.5 ALGO

## Participants

![Reverse](https://user-images.githubusercontent.com/23183451/152804363-5db300eb-481e-450f-bf7e-8bcd0cf7f732.png)

**Auctioneer** sets the auction parameters such as token, start price, and floor price.

**Depositer** Takes after the auctioneer, depositing the token. The depositor is the same account as the Auctioneer.

**Relay** follows after the auction is closed. It is that last participant.

## Views
In the views accessible through the contract handle in the frontend, there is 1 named view called Auction.
### Auction
The auction view provides access to the various states of the auction such as token and current price.
#### token
Token is the asset up for auction.
#### currentPrice
Current price is the price that the auction may be resolved.
#### startPrice
Start price is the price at the begining of the auction.
#### floorPrice
Floor price is the lowest price throught the auction.
#### closed
Closed is the closed state of the auction, true or false.
## API

![Reverse3](https://user-images.githubusercontent.com/23183451/152784003-2915f72d-0c0d-429e-aac5-a69ff601d67b.png)

**Bid** is the name of the API that allows interaction with a live auction.

**touch** allows activation of the price function. Note, the price may not be manipulated by repetitive touch api calls.

**acceptOffer** resolves the auction as sale.

**cancel** resolves the auction as no sale.

## Steps

1. Auctioneer sets up auction
1. Token is deposited
1. Enter api (can accept/touch)
1. Relay deletes app

## quickstart

commands
```bash
git clone git@github.com:ZestBloom/reverse.git
cd reverse
source np.sh
np
```

output
```json
{"info":66944916}
```

## how does it work

NP provides a nonintrusive wrapper allowing apps to be configurable before deployment and created on the fly without incurring global storage.   
Connect to the constructor and receive an app id.   
Activate the app by paying for deployment and storage cost. 
After activation, your RApp takes control.

## how to activate my app

In your the frontend of your NPR included Contractee participation. Currently, a placeholder fee is required for activation. Later an appropriate fee amount will be used.

```js
ctc = acc.contract(backend, id)
backend.Contractee(ctc, {})
```

## terms

- NP - Nash Protocol
- RAap - Reach App
- NPR - NP Reach App
- Activation - Hand off between constructor and contractee require fee to pay for deployment and storage cost incurred by constructor

## dependencies

- Reach development environment (reach compiler)
- sed - stream editor
- grep - pattern matching
- curl - request remote resource


