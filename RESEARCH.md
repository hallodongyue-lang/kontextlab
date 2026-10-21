# KontextLab 3.0 · Research protocol

## Scope
Community classification is an operational consensus, not accuracy or a platform enforcement verdict. Editorial samples are fictional and never counted as human votes. Advanced filters combine text, final/proposed label, social relationship, setting, linguistic phenomenon and disagreement. Unspecified dimensions remain unknown. Initial editorial enrichment uses only explicit contexts; `research_meta.source = editorial-1.0`. Community metadata is contributor-reported.

## Context comparison / context-1.0
Three expressions × three relationships = nine fictional conditions. Participants lock an initial interpretation before context is revealed, then record an interpretation and a reason. Results are exploratory repeated measures, with self-selected conditions and no randomization. Contexts differ in events as well as relationship: this is not a controlled estimate of the isolated effect of social relationship. No correct answer or causal inference is claimed. Each account has at most one extant record per condition. Deleting a record allows a later resubmission, so summaries are records, not unique participants. Participants may see other conditions and aggregate results; this can influence later answers.

## Disagreement
Consensus uses the existing 60% publication protocol. A separate research flag uses >=5 votes and a leading non-reject label share below80%; exactly80% is not flagged. Rejections stay in the denominator. Shannon entropy in bits measures dispersion over all ballot categories including rejection; no vote means missing entropy, not zero. Public disagreement tables show only published/withdrawn cases to protect independent pending review. Reasons require a separate per-review opt-in. Earlier reasons default to private.

## Privacy and exports
Raw experiment records and reasons are owner-only under RLS. Public aggregates contain only consented, non-withdrawn choices; experiment reasons are never exported publicly. Public rationale exports remove user IDs and timestamps but free text may still identify people; this is de-identification, not guaranteed anonymity. Downloads cannot be recalled. Public sample texts should already be fictional/de-identified.

CSV/JSON corpus exports respect current filters across all pages, with source, metadata, labels, ballot statistics and opted-in reasons. Pending ballot distributions are omitted until the viewer has reviewed that case. Formula-leading CSV cells are escaped. Private research export is available on the privacy page. Owners may withdraw/restore experiments or permanently delete individual records after an explicit in-product confirmation. Shared review reasons can be withdrawn independently without altering classification votes. Existing comments can be deleted by their authors. Sample privacy removal uses the existing report queue; account-wide deletion requires maintainer handling and is not automated.

## Validation
Node regression tests cover translations, thresholds, entropy, combined filters, escaping and CSV injection. Transactional database checks cover owner-only access, forged ownership rejection, opt-in aggregation, withdrawal and default-private behavior. Tests run inside rolled-back transactions and do not create public research observations. Browser checks cover the two-stage experiment, filters, downloads, navigation and localized views. No claim of GDPR certification, representative sampling or causal validity is made.
