![Reverse](https://user-images.githubusercontent.com/23183451/152773597-a8b9935c-cfa4-4ca9-a71b-d9c4e839ce37.png)

# Reverse

Reverse is a reach app, similar to auction, in which an ASA holder to auction an asset for ALGOs. It allows buying and price discovery on the asset during the auction. After the end of the auction time the contract can be closed out resulting in payouts to the seller, marketplace, creator and a transfer of the asset to the buyer. Reverse auctions begin at some start price and work down to a floor price.

## Activation

0.5 ALGO

## Participants
### Auctioneer
The Auctioneer sets the auction parameters such as token, start price, and floor price.
### Depositer
After the parameters are received from the Auctioneer, the Depoisiter takes over. The depoisiter is the same account as the Auctioneer.
### Relay
After the auction is closed. The Relay is that last participant.
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
In the api accessible through the contract handle in the frontend, there is 1 named api called Bid.
### Bid
Bid allows you to interact with the live auction.
#### touch
Touch allow you to update the current price. The current price is relative to start price, floor price, and blocks since start of auction. It cannot be manipulated by repetative touch api calls.
#### acceptOffer
Accept offer will resolved the auction, transfering ownership to the buyer and payment to the seller.

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


