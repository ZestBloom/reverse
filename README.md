# Reverse

Reverse is a reach app, similar to auction, in which an ASA holder to auction an asset for ALGOs. It allows buying and price discovery on the asset during the auction. After the end of the auction time the contract can be closed out resulting in payouts to the seller, marketplace, creator and a transfer of the asset to the buyer. Reverse auctions begin at some start price and work down to a floor price.

## Activation

0.5 ALGO

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


