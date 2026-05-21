package org.cashu.wallet.Core.Protocols

import org.cashu.wallet.Models.PaymentMethodKind

interface PaymentMethodSupport {
    fun supportsMint(method: PaymentMethodKind): Boolean
    fun supportsMelt(method: PaymentMethodKind): Boolean
}
