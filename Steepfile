# Steepfile for type checking

target :lib do
  signature "sig"

  check "lib"

  # Standard library
  library "base64"
  library "json"
  library "net-http"
  library "uri"

  configure_code_diagnostics do |hash|
    hash[Steep::Diagnostic::Ruby::UnannotatedEmptyCollection] = :hint
    hash[Steep::Diagnostic::Ruby::UnknownConstant] = :hint
    hash[Steep::Diagnostic::Ruby::NoMethod] = :hint
    hash[Steep::Diagnostic::Ruby::UnresolvedOverloading] = :hint
    hash[Steep::Diagnostic::Ruby::IncompatibleAssignment] = :hint
    hash[Steep::Diagnostic::Ruby::ArgumentTypeMismatch] = :hint
    hash[Steep::Diagnostic::Ruby::ReturnTypeMismatch] = :hint
    hash[Steep::Diagnostic::Ruby::BlockTypeMismatch] = :hint
    hash[Steep::Diagnostic::Ruby::BreakTypeMismatch] = :hint
    hash[Steep::Diagnostic::Ruby::ImplicitBreakValueMismatch] = :hint
    hash[Steep::Diagnostic::Ruby::UnexpectedBlockGiven] = :hint
    hash[Steep::Diagnostic::Ruby::UnexpectedPositionalArgument] = :hint
  end
end
