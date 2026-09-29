# Polar owner-only steps

These account actions require the owner's identity and payout details. Do not send documents or bank details to an agent or commit them.

1. Open [Polar production](https://polar.sh/), sign up with your own account, and create the writeitdown organization. Keep the production organization separate from [Polar sandbox](https://sandbox.polar.sh/), which requires its own sign-in.
2. In the production dashboard, follow **Finance → Account → Submit for approval** and complete the business/account review and personal identity verification (KYC). See [Polar account reviews](https://polar.sh/docs/merchant-of-record/account-reviews). Answer using your real product and `https://writeitdown.app/`.
3. In **Finance → Accounts**, connect a **Stripe Connect Express payout account** and provide the owner's IBAN/bank details there, not to an agent. See [Polar payout accounts](https://polar.sh/docs/features/finance/accounts). Polar requires this before accepting live payments.
4. Confirm a working support mailbox (proposed `support@writeitdown.app` if it exists) and the legal copyright holder (Info.plist currently says `writeitdown`, source LICENSE still says `Your Company`). Send only the confirmed public values to the implementation worker.
5. After approval, give the implementation worker the non-secret production organization UUID, license-key benefit UUID, and hosted checkout URL. The worker creates/verifies the USD $4.99 product and signs the final DMG; you approve final icon, site copy, upload and site deployment. Never send a Polar access token, license key, identity document, or IBAN in chat.
