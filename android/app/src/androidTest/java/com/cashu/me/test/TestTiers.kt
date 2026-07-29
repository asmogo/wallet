package com.cashu.me.test

/** Excluded from the required PR suite; exercised by nightly and release CI. */
@Target(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION)
@Retention(AnnotationRetention.RUNTIME)
annotation class FullOnly

/** Small cross-device behavior pack used by compatibility managed devices. */
@Target(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION)
@Retention(AnnotationRetention.RUNTIME)
annotation class Compatibility
