# Article Bias Engine

**Status:** Required MVP architecture
**Decision:** Article-level Left, Center, Right, or N/A must be immediately visible in the feed and reader. Analysis stays on the device.

## Answer

Yes. The phone can examine the normalized article locally and assign an article-level leaning. The strongest implementation is not a single unconstrained LLM prompt. It is a local ensemble built for speed, calibration, and explainability.

## Local inference stack

### 1. Political relevance gate

A small bundled Core ML text classifier first decides whether the article contains meaningful political framing. Sports, weather, product reviews, routine science, and other nonpolitical reporting become N/A without asking a general-purpose language model to invent an ideology.

### 2. Dedicated article-lean classifier

A compact transformer fine-tuned for Left, Center, and Right runs through Core ML. It receives only normalized article content:

- Headline and dek.
- Lead section.
- Representative middle sections.
- Conclusion.
- Quotations and their framing.

Publisher name, domain, author, URL, source-rating label, navigation, ads, and boilerplate are removed. This prevents the article classifier from simply learning that a publisher usually belongs to one side.

Long articles are classified in semantic chunks. Chunk probabilities are aggregated with extra weight on headline/dek, lead, and conclusion. The output is cached with the article and model version.

### 3. Apple on-device Foundation Model

On compatible Apple Intelligence devices, the Foundation Models framework runs as an independent local judge and explanation generator. Apple's documentation confirms that the system language model runs on device, supports guided structured generation, and has a 4096-token context window. The app therefore supplies selected article chunks rather than blindly sending an entire long article.

The guided result is constrained to:

- `left`
- `center`
- `right`
- `notApplicable`
- confidence
- short rationale
- evidence spans from the supplied text

The model does not receive the publisher identity or source baseline.

### 4. Calibrated aggregator

The final label considers:

- Political relevance.
- Dedicated Core ML classifier output.
- Chunk-to-chunk consistency.
- Foundation Models result when available.
- Extraction completeness.

Agreement produces higher confidence. Strong disagreement, weak evidence, nonpolitical content, or incomplete extraction produces N/A rather than confident-looking noise.

## Immediate availability

Analysis runs eagerly during feed refresh, after article extraction and before normal presentation. Results are cached. In ordinary use, the label is already present when the story card appears and remains identical when the article opens.

A newly discovered item that has not finished analysis may briefly show `Analyzing locally`, but the ingestion pipeline should prioritize headline/dek plus lead classification so this state is short. Real latency must be benchmarked on Brian's actual iPhone and iPad before promising a threshold.

## Device coverage

- **Apple Intelligence devices:** Dedicated Core ML classifier plus Foundation Models cross-check and rationale.
- **Other supported iPhones/iPads:** Dedicated Core ML classifier only. This remains fully local and still supplies the required label.
- **No usable article body:** N/A with `Insufficient article content` in the explanation sheet.

A future custom adapter for Apple's system model is possible using Apple's Foundation Models adapter training toolkit, but it should only be attempted after the unadapted ensemble is benchmarked. The dedicated Core ML model remains important because it is stable, testable, and available beyond Apple Intelligence hardware.

## User interface

### Feed

The bias label remains immediately visible on every article card:

- **LEFT**
- **CENTER**
- **RIGHT**
- **N/A**

The Gemini visual direction remains the base. The badge stays near the headline, uses the muted sage/ochre/terracotta/slate palette, and includes an accessibility label that says it is an on-device article estimate.

### Article header

The article-level label remains prominent beside the publisher metadata. Tapping it opens a sheet with:

- Article estimate.
- Confidence: High, Medium, or Low.
- `Analyzed privately on this device`.
- Short rationale.
- Supporting article excerpts.
- Model and analysis version.
- Separate publisher baseline and its external provider.
- A manual correction control for evaluation and future personalization.

### Important separation

`Article leaning: Center` is computed from the article text.

`Publisher baseline: Center-Left, AllSides` is separately sourced publisher context.

The app never silently blends these into one number. Their disagreement is useful information.

## Evaluation standard

A bias classifier can appear accurate while merely memorizing publishers. Random article splits are insufficient. Evaluation must include:

1. Publisher-held-out test splits.
2. Event/topic-held-out test splits.
3. Balanced Left, Center, Right, and nonpolitical/N/A examples.
4. Confusion matrix and macro-F1.
5. Confidence calibration and abstention coverage.
6. A manually reviewed set of current articles from publishers absent from training.
7. Comparison of Core ML, Foundation Models, and ensemble outputs.
8. Regression tests whenever the extraction engine or model changes.

The acceptance test is not raw accuracy alone. The label must be useful on unseen publishers, honest when uncertain, and stable enough that the same article does not flip because metadata changed.

## Data considerations

Candidate research corpora include the 34,737-article dataset released with Baly et al., `We Can Detect Your Bias`, and QBias's 21,747 articles derived from AllSides balanced-news roundups. Licenses and redistribution rights must be verified before training or packaging any derivative model.

Recent research also warns that political-bias predictors often focus on publisher-specific cues rather than article semantics. That is why publisher identity is excluded from inference and why publisher-held-out evaluation is mandatory.

## Primary references

- Apple Foundation Models: https://developer.apple.com/documentation/foundationmodels/
- Apple context-window guidance: https://developer.apple.com/documentation/foundationmodels/managing-the-context-window
- Apple adapter training toolkit: https://developer.apple.com/apple-intelligence/foundation-models-adapter/
- Apple Create ML text classifier: https://developer.apple.com/documentation/createml/mltextclassifier
- Baly et al., 2020: https://aclanthology.org/2020.emnlp-main.404/
- Article Bias Prediction repository: https://github.com/ramybaly/Article-Bias-Prediction
- QBias dataset: https://github.com/irgroup/Qbias
