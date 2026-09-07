"""Nutshell with explicit incoming payments, using its real ledger and proofs.

Only the Lightning backend is controlled. No auto-credit occurs: tests must pay
an invoice through /test/pay or melt it through this backend.
"""
from bolt11 import decode
from cashu.lightning.base import PaymentResult
from cashu.lightning.fake import FakeWallet
import cashu.lightning


class ControlledFakeWallet(FakeWallet):
    async def mark_invoice_paid(self, invoice, delay=True):
        # get_invoice_status may call this again; the ledger event is idempotent.
        if invoice in self.paid_invoices_incoming:
            return
        self.paid_invoices_incoming.append(invoice)
        await self.paid_invoices_queue.put(invoice)
        self.update_balance(invoice, incoming=True)

    async def pay_invoice(self, quote, fee_limit):
        result = await super().pay_invoice(quote, fee_limit)
        if result.result == PaymentResult.SETTLED:
            await self.mark_invoice_paid(decode(quote.request))
        return result


cashu.lightning.ControlledFakeWallet = ControlledFakeWallet
from cashu.mint.app import app
from cashu.mint.startup import backends
from cashu.core.base import Method, Unit
from fastapi import HTTPException, Request


@app.post("/test/pay")
async def pay(request: Request):
    payment = decode((await request.json())["invoice"])
    backend = backends[Method.bolt11][Unit.sat]
    if not any(i.payment_hash == payment.payment_hash for i in backend.created_invoices):
        raise HTTPException(404, "Invoice does not belong to the controlled mint")
    await backend.mark_invoice_paid(payment)
    return {"paid": True}
