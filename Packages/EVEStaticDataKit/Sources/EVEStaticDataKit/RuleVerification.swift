public enum IndustryRuleVerificationStatus:
    String,
    Codable,
    Equatable,
    Sendable
{
    case verified
    case provisional
    case needsReview
}

public enum IndustryPreflightResult:
    String,
    Codable,
    Equatable,
    Sendable
{
    case pass
    case fail
    case needsReview
}
