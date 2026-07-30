import Foundation

/// A cluster of independent reports on the same event.
public struct CoverageCluster: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let articles: [ArticleDocument]

    public init(id: String, title: String, articles: [ArticleDocument]) {
        self.id = id
        self.title = title
        self.articles = articles
    }

    /// Distribution of the *publishers'* externally sourced baselines. This is
    /// deliberately not built from article estimates: the strip describes who is
    /// covering the story, not what any single article was judged to be.
    public var baselineDistribution: [(bucket: BaselineBucket, count: Int)] {
        let buckets = articles.map { BaselineBucket(rating: $0.publisher.baseline?.rating) }
        return BaselineBucket.allCases.compactMap { bucket in
            let count = buckets.filter { $0 == bucket }.count
            return count > 0 ? (bucket, count) : nil
        }
    }
}

public struct EditionContent: Equatable, Sendable {
    public let editionDate: Date
    public let lead: ArticleDocument
    public let cluster: CoverageCluster
    public let river: [ArticleDocument]

    public var allArticles: [ArticleDocument] {
        [lead] + cluster.articles + river
    }
}

/// Bundled fictional journalism.
///
/// Every publisher, byline, quotation, place, and illustration in this file is
/// invented for development. Nothing here reproduces or paraphrases real
/// reporting, and no illustration is credited to a real photographer or agency.
/// It exists so the app is useful offline and so screenshots and tests are
/// deterministic.
public enum DemoEdition {
    public static let disclosure =
        "Demo edition. Publishers, bylines, and stories on this screen are fictional development data."

    private static func url(_ publisher: Publisher, _ path: String) -> URL {
        URL(string: "https://\(publisher.domain)/\(path)")!
    }

    private static func credit(_ subject: String) -> String {
        "Illustration by Broadsheet for demo data — \(subject)"
    }

    public static func edition(referenceDate: Date = Date()) -> EditionContent {
        func ago(_ minutes: Int) -> Date {
            referenceDate.addingTimeInterval(TimeInterval(-minutes * 60))
        }

        return EditionContent(
            editionDate: referenceDate,
            lead: leadStory(publishedAt: ago(108)),
            cluster: CoverageCluster(
                id: "cluster.water-allocation-remand",
                title: "Federal Court Sends the Western Water Allocation Rule Back to the Agency",
                articles: [
                    clusterMeridian(publishedAt: ago(64)),
                    clusterDelta(publishedAt: ago(122)),
                    clusterNorthgate(publishedAt: ago(181)),
                    clusterBasinRadio(publishedAt: ago(238))
                ]
            ),
            river: [
                rentStabilization(publishedAt: ago(300)),
                licensingRules(publishedAt: ago(372)),
                kelpBloom(publishedAt: ago(447)),
                transitFares(publishedAt: ago(516)),
                portBerth(publishedAt: ago(603))
            ]
        )
    }

    // MARK: - Lead story

    private static func leadStory(publishedAt: Date) -> ArticleDocument {
        let publisher = DemoPublishers.meridianWire
        let canonical = url(publisher, "energy/summer-reserve-margins-filing")

        return ArticleDocument(
            id: ArticleID(canonicalURL: canonical),
            canonicalURL: canonical,
            publisher: publisher,
            kicker: "Energy",
            title: "Grid Operators Warn Summer Reserve Margins Are Thinner Than Forecast",
            dek: "Three regional operators told federal regulators this week that projected August reserves fall below their own planning targets, citing delayed transmission upgrades and a hotter overnight load.",
            author: "Adaeze Okonjo",
            publishedAt: publishedAt,
            heroImage: ArticleImage(
                artwork: .duskTransmissionLines,
                aspectRatio: 16.0 / 9.0,
                altText: "Transmission towers crossing dry hills at dusk, with a low sun behind them.",
                caption: "Transmission lines outside the Kestrel Bend substation, where a reconductoring project slipped past its scheduled completion.",
                credit: credit("Kestrel Bend corridor")
            ),
            blocks: [
                .paragraph(RichText(runs: [
                    .plain("Three of the country's regional grid operators told federal regulators on Tuesday that their projected reserve margins for August have fallen below internal planning targets, a shift they attributed to transmission upgrades running behind schedule and to overnight temperatures that no longer let equipment cool. The filings, submitted ahead of a scheduled reliability hearing, do not forecast outages. They ask the commission to treat the summer as a narrower operating window than last year's assessment described."),
                ])),
                .paragraph(RichText(runs: [
                    .plain("Reserve margin is the cushion between expected demand at peak and the generation an operator can call on. Planners size it for the hour when everything is worst at once: high load, weak wind, an unplanned outage at a large plant. The operators' "),
                    .link(text: "joint filing", url: url(publisher, "documents/reliability-filing-august")),
                    .plain(" puts that cushion between 13 and 16 percent across the three territories, against internal targets that range from 15 to 18.")
                ])),
                .heading("What the filings say"),
                .paragraph(RichText("None of the three operators reported a shortfall in generating capacity itself. Each pointed instead to delivery: the lines and substations that move power from where it is produced to where it is used at 7 p.m. on a hot day. Two reconductoring projects that were expected to be energised by June are now scheduled for late September, and a third has no revised date on the record.")),
                .list(ordered: false, items: [
                    RichText("A 230-kilovolt rebuild in the northern corridor, delayed by a transformer lead time the operator described as eleven months and lengthening."),
                    RichText("A substation expansion held for a wetland review that the agency has not yet closed."),
                    RichText("A planned intertie upgrade whose contractor withdrew in March and has not been replaced.")
                ]),
                .pullQuote(
                    text: "We are not short of electrons. We are short of the wire that carries them on the four afternoons a year when it matters.",
                    attribution: "Priya Raghunathan, reliability planner, Kestrel Bend Operating Authority"
                ),
                .heading("Where the margin went"),
                .paragraph(RichText("Load has also changed shape. Operators have spent a decade planning for a single afternoon peak, but the filings describe a second, flatter shoulder that now persists past ten at night, when solar output is gone and equipment that used to shed heat overnight does not. One operator wrote that its summer overnight minimum has risen by roughly four percent in three years, which matters less for capacity than for maintenance windows: crews have fewer safe hours to take a line out of service.")),
                .image(ArticleImage(
                    artwork: .rangeRoad,
                    aspectRatio: 3.0 / 2.0,
                    altText: "A service road running along a ridge with utility poles at intervals.",
                    caption: "The northern corridor rebuild has been rescheduled twice, most recently for a transformer that has not shipped.",
                    credit: credit("northern corridor")
                )),
                .paragraph(RichText(runs: [
                    .plain("The commission's staff has asked for supplemental data by 14 August, including the assumptions behind each operator's demand forecast. A staff memo circulated last month noted that the three operators use different definitions of a planning reserve, which has made their numbers hard to compare. The commission has "),
                    .link(text: "opened a docket", url: url(publisher, "documents/reliability-docket-notice")),
                    .plain(" on standardising that definition, though any rule from it would arrive long after this summer.")
                ])),
                .divider,
                .paragraph(RichText("State officials in two of the three territories said they had not been asked to prepare conservation appeals and did not expect to. A third declined to characterise its planning. The reliability hearing is scheduled for 21 August."))
            ],
            contentSource: .bundledFixture
        )
    }

    // MARK: - Coverage cluster

    private static func clusterMeridian(publishedAt: Date) -> ArticleDocument {
        let publisher = DemoPublishers.meridianWire
        let canonical = url(publisher, "law/water-allocation-rule-vacated")

        return ArticleDocument(
            id: ArticleID(canonicalURL: canonical),
            canonicalURL: canonical,
            publisher: publisher,
            kicker: "Courts",
            title: "Appeals Court Vacates Water Allocation Rule, Orders New Rulemaking",
            dek: "The panel held that the agency did not adequately explain its departure from the prior allocation formula, and returned the rule without ruling on the formula itself.",
            author: "Tomas Beaulieu",
            publishedAt: publishedAt,
            heroImage: ArticleImage(
                artwork: .riverDelta,
                altText: "A braided river delta seen from above, with irrigation squares along one bank.",
                caption: "The allocation rule governs deliveries across four irrigation districts in the lower basin.",
                credit: credit("lower basin delta")
            ),
            blocks: [
                .paragraph(RichText("A federal appeals court vacated the basin water allocation rule on Wednesday and sent it back to the agency for a new rulemaking, holding that the agency had not adequately explained why it departed from the allocation formula it used for the previous eleven years.")),
                .paragraph(RichText("The panel was explicit about what it did not decide. In a twenty-two page opinion, the court wrote that the new formula might well be defensible, but that the record before it did not show the agency had considered the reliance interests of districts that had planned around the old one.")),
                .heading("What happens now"),
                .paragraph(RichText("Vacatur takes effect in ninety days. Until then the challenged rule remains operative, which means deliveries scheduled for this season proceed as published. The agency may appeal, begin a new rulemaking, or ask the court to leave the rule in place while it does the latter.")),
                .pullQuote(
                    text: "An agency may change its mind. It must say why, and it must say what it did with the arguments against.",
                    attribution: "From the panel's opinion"
                ),
                .paragraph(RichText("Both the districts that brought the challenge and the environmental intervenors that opposed them described the outcome as partial. Counsel for the districts said the ruling restores a planning baseline; counsel for the intervenors noted that the court declined to disturb the agency's underlying authority to reallocate at all.")),
                .paragraph(RichText("A spokesperson for the agency said it was reviewing the opinion and had not decided on its next step."))
            ],
            contentSource: .bundledFixture
        )
    }

    private static func clusterDelta(publishedAt: Date) -> ArticleDocument {
        let publisher = DemoPublishers.deltaReview
        let canonical = url(publisher, "basin/certainty-lost-water-ruling")

        return ArticleDocument(
            id: ArticleID(canonicalURL: canonical),
            canonicalURL: canonical,
            publisher: publisher,
            kicker: "Analysis",
            title: "Basin Towns and Working Families Lose the Certainty They Spent Four Years Arguing For",
            dek: "The court's remand hands another season of uncertainty to the frontline communities that have the least room to absorb it.",
            author: "Lucía Ferreira",
            publishedAt: publishedAt,
            blocks: [
                .paragraph(RichText("For four years the towns at the bottom of the basin have asked for one thing: a number they can plan around. Wednesday's ruling does not give them one. It sends the allocation rule back to an agency that has been underfunded through three consecutive budgets and told to explain itself more carefully.")),
                .paragraph(RichText("The districts that brought the challenge are not the households that will feel the remand first. Frontline communities in the lower basin — the ones whose wells went dry in the 2024 drawdown — were not parties to the case at all, and the working families who staff the packing sheds do not get a seat at a rulemaking table that meets on weekday mornings in the capital.")),
                .heading("Who absorbs the delay"),
                .paragraph(RichText("Watchdogs warn that a second rulemaking will take at least eighteen months, and that the interim will be governed by the same rule the court just called inadequately explained. Public investment in the metering programme that would make any formula enforceable has been deferred twice. Without it, the argument about allocation is an argument about numbers nobody can verify.")),
                .list(ordered: true, items: [
                    RichText("A remand that leaves the contested rule operating for another season."),
                    RichText("A metering programme funded at roughly a third of what the agency's own estimate called adequate."),
                    RichText("Two towns already trucking in drinking water three months earlier than they did last year.")
                ]),
                .pullQuote(
                    text: "We were told to be patient through the litigation. Now we are told to be patient through the rewrite.",
                    attribution: "Alma Restrepo, water board chair, Palo Verde Townsite"
                ),
                .paragraph(RichText("None of this makes the panel wrong on the law. It makes the remedy expensive, and it puts the cost on the people least able to carry it."))
            ],
            contentSource: .bundledFixture
        )
    }

    private static func clusterNorthgate(publishedAt: Date) -> ArticleDocument {
        let publisher = DemoPublishers.northgateJournal
        let canonical = url(publisher, "opinion/agency-skipped-cost-analysis")

        return ArticleDocument(
            id: ArticleID(canonicalURL: canonical),
            canonicalURL: canonical,
            publisher: publisher,
            kicker: "Commentary",
            title: "The Court Faulted the Agency for Skipping the Cost Analysis It Promised",
            dek: "A rule written without the promised accounting of compliance costs was always going to come back, and the districts that warned about it were right.",
            author: "Grant Weatherby",
            publishedAt: publishedAt,
            blocks: [
                .paragraph(RichText("The agency promised a cost analysis when it opened this docket in 2022. It did not produce one. On Wednesday a federal panel vacated the resulting rule, and the reasoning is worth reading for anyone who has argued that the regulatory burden of a rule is a fact to be measured rather than a talking point to be dismissed.")),
                .paragraph(RichText("Irrigation districts spent four years telling unelected bureaucrats that the compliance costs of the new formula would land on operators who cannot pass them along. The record shows those comments were filed, acknowledged, and then not addressed. That is not a technicality. Notice and comment means the answers have to appear somewhere.")),
                .heading("What the taxpayer paid for"),
                .paragraph(RichText("Taxpayer dollars funded four years of proceedings that produced a rule the court has now sent back. A second rulemaking will cost more. The red tape here is not the requirement to explain a decision; it is the habit of issuing rules first and constructing the justification afterwards, which guarantees the second round.")),
                .pullQuote(
                    text: "Explain the cost, or expect to do this twice.",
                    attribution: nil
                ),
                .paragraph(RichText("None of which decides whether the new formula is right. The panel was careful to say it was not reaching that question. But an agency that treats its own promised analysis as optional should not be surprised when a court treats its conclusions the same way."))
            ],
            contentSource: .bundledFixture
        )
    }

    private static func clusterBasinRadio(publishedAt: Date) -> ArticleDocument {
        let publisher = DemoPublishers.basinPublicRadio
        let canonical = url(publisher, "explainer/what-the-water-ruling-changes")

        return ArticleDocument(
            id: ArticleID(canonicalURL: canonical),
            canonicalURL: canonical,
            publisher: publisher,
            kicker: "Explainer",
            title: "What the Water Ruling Changes for Irrigation Districts This Season",
            dek: "Deliveries already scheduled will not change before autumn. Here is what the agency has to do next, and when.",
            author: "Ruth Nakamura",
            publishedAt: publishedAt,
            blocks: [
                .paragraph(RichText("The short answer for this season is: very little. The court vacated the allocation rule but delayed the effect of that vacatur by ninety days, so deliveries published for the summer proceed as scheduled.")),
                .heading("The timeline"),
                .list(ordered: true, items: [
                    RichText("Ninety days from Wednesday, the rule leaves the books unless the agency obtains a stay."),
                    RichText("A new rulemaking would begin with a notice, followed by a comment period of at least sixty days."),
                    RichText("The prior formula governs in the interim, which is what the districts asked for.")
                ]),
                .paragraph(RichText("The agency has three options and has not said which it will take: appeal, ask the panel to leave the rule in place during a rewrite, or start the rewrite immediately. Each has a different consequence for the winter deliveries that are usually set in November.")),
                .heading("What the court did not decide"),
                .paragraph(RichText("The panel did not rule on whether the new formula was a good one, and it did not question the agency's authority to change the formula at all. Its objection was to the explanation, which is a narrower finding than either side's summary of it suggests.")),
                .paragraph(RichText("The commission's public docket carries the full opinion and the comment record, and the agency has said it will post any procedural notice there first."))
            ],
            contentSource: .bundledFixture
        )
    }

    // MARK: - River

    private static func rentStabilization(publishedAt: Date) -> ArticleDocument {
        let publisher = DemoPublishers.harborAndMain
        let canonical = url(publisher, "city/rent-stabilization-expansion-vote")

        return ArticleDocument(
            id: ArticleID(canonicalURL: canonical),
            canonicalURL: canonical,
            publisher: publisher,
            kicker: "City Hall",
            title: "Council Approves Rent Stabilization Expansion After a Six-Hour Hearing",
            dek: "The ordinance extends coverage to buildings finished before 2009 and adds a complaint process for price gouging in the months after a sale.",
            author: "Devon Ashworth",
            publishedAt: publishedAt,
            heroImage: ArticleImage(
                artwork: .rowHouses,
                altText: "A row of narrow houses with bay windows along a sloping street.",
                caption: "Buildings completed before 2009 come under the ordinance in January.",
                credit: credit("Harbor Street row houses")
            ),
            blocks: [
                .paragraph(RichText("The council voted seven to four on Tuesday night to extend rent stabilization to buildings completed before 2009, ending a six-hour hearing in which more than ninety residents spoke. The expansion brings roughly eleven thousand additional units under the ordinance beginning in January.")),
                .paragraph(RichText("Supporters framed the vote as an affordable housing measure for working families who have watched increases outpace wages for a decade. The ordinance also creates a complaint process for price gouging in the twelve months after a building changes hands, a pattern tenant organisers documented in three neighbourhoods last year.")),
                .pullQuote(
                    text: "We are not asking for a subsidy. We are asking for a rent we can predict when the building sells.",
                    attribution: "Renata Oyelaran, tenant council member"
                ),
                .paragraph(RichText("Opponents on the council argued the threshold will slow permitting for mid-size projects, and two members said they would return in the autumn with an amendment exempting buildings under twelve units. Landlord associations have not said whether they will challenge the ordinance.")),
                .paragraph(RichText("The housing department has ninety days to publish implementation rules, including how the complaint process will be staffed."))
            ],
            contentSource: .bundledFixture
        )
    }

    private static func licensingRules(publishedAt: Date) -> ArticleDocument {
        let publisher = DemoPublishers.ninthStreetDispatch
        let canonical = url(publisher, "business/licensing-rules-unworkable")

        return ArticleDocument(
            id: ArticleID(canonicalURL: canonical),
            canonicalURL: canonical,
            publisher: publisher,
            kicker: "Business",
            title: "Small Business Owners Say the New Licensing Rules Are Unworkable",
            dek: "A revised trade licence adds two inspections and a quarterly filing, and the shops that have to do the paperwork say nobody costed the hours.",
            author: "Marguerite Vinson",
            publishedAt: publishedAt,
            blocks: [
                .paragraph(RichText("Small business owners packed a hearing room on Monday to tell the licensing board that the revised trade licence is unworkable as written. The rule adds two inspections and a quarterly filing to a permit that previously renewed once a year.")),
                .paragraph(RichText("Several owners said the compliance costs are not in the fee but in the hours. A four-person shop that closes for an inspection loses a day's trade, and the quarterly filing requires a bookkeeper most of them do not employ. The board's own estimate put the added burden at ninety minutes per quarter, a figure three witnesses called unrecognisable.")),
                .list(ordered: false, items: [
                    RichText("Two scheduled inspections, replacing one."),
                    RichText("A quarterly filing with no small-operator exemption."),
                    RichText("A fee schedule unchanged since 2019, which the board cited as evidence the rule is not burdensome.")
                ]),
                .pullQuote(
                    text: "The fee is not the problem. The red tape around the fee is the problem.",
                    attribution: "Óscar Delgado-Marín, owner, Ninth and Palmer Hardware"
                ),
                .paragraph(RichText("Board members were divided. Two described the objections as the predictable cost of a safety regime that had gone twelve years without review; a third said the process looked like government overreach applied to the operators least able to absorb it and asked staff to return with a tiered proposal.")),
                .paragraph(RichText("A vote is scheduled for September."))
            ],
            contentSource: .bundledFixture
        )
    }

    private static func kelpBloom(publishedAt: Date) -> ArticleDocument {
        let publisher = DemoPublishers.cascadeLedger
        let canonical = url(publisher, "science/early-kelp-bloom-sable-cape")

        return ArticleDocument(
            id: ArticleID(canonicalURL: canonical),
            canonicalURL: canonical,
            publisher: publisher,
            kicker: "Science",
            title: "Marine Biologists Track an Unusually Early Kelp Bloom Off Sable Cape",
            dek: "Divers recorded canopy growth six weeks ahead of the ten-year average, and the lab that has surveyed the reef since 1998 is not yet sure why.",
            author: "Ingrid Solheim",
            publishedAt: publishedAt,
            heroImage: ArticleImage(
                artwork: .harborGantries,
                aspectRatio: 4.0 / 3.0,
                altText: "A calm harbour with gantry cranes silhouetted against morning haze.",
                caption: "The survey team works out of the old fishing pier at Sable Cape.",
                credit: credit("Sable Cape harbour")
            ),
            blocks: [
                .paragraph(RichText("Divers surveying the reef off Sable Cape recorded canopy-forming kelp six weeks earlier than the ten-year average for the site, the earliest onset since the survey began in 1998.")),
                .paragraph(RichText("The lab that runs the survey is careful about what the measurement means. A single early season is weather, not a trend, and the same reef produced an unusually late bloom two years ago. What makes this year interesting is the water column: temperature at ten metres has been about half a degree cooler than usual since April, and nitrate concentrations have stayed high through a period when they normally fall.")),
                .heading("What the divers measured"),
                .list(ordered: false, items: [
                    RichText("Canopy density at three fixed transects, counted by hand on the same schedule since 1998."),
                    RichText("Water temperature and nitrate at five and ten metres."),
                    RichText("Urchin counts, which have fallen for a third consecutive year at the northern transect.")
                ]),
                .pullQuote(
                    text: "The honest answer is that we have one good year and three plausible explanations, and we cannot yet tell them apart.",
                    attribution: "Dr Marisol Enríquez, Sable Cape Reef Survey"
                ),
                .paragraph(RichText("The urchin decline may matter most. Urchins graze young kelp, and their numbers at the northern transect have fallen by roughly half since a wasting outbreak in 2023. Whether the early canopy reflects cooler water, fewer grazers, or the ordinary variance of a shallow reef will take several more seasons to separate.")),
                .paragraph(RichText("The survey publishes its raw transect counts each autumn."))
            ],
            contentSource: .bundledFixture
        )
    }

    private static func transitFares(publishedAt: Date) -> ArticleDocument {
        let publisher = DemoPublishers.meridianWire
        let canonical = url(publisher, "transit/fare-decision-delayed")

        return ArticleDocument(
            id: ArticleID(canonicalURL: canonical),
            canonicalURL: canonical,
            publisher: publisher,
            kicker: "Transit",
            title: "Regional Transit Board Delays a Fare Decision Until September",
            dek: "Directors postponed a vote on the fare schedule after staff said the ridership model behind it predates the new commuter rail timetable.",
            author: "Callum Whitfield",
            publishedAt: publishedAt,
            blocks: [
                .paragraph(RichText("The regional transit board postponed a scheduled vote on next year's fare schedule, asking staff to rerun the ridership model with the commuter rail timetable that took effect in May.")),
                .paragraph(RichText("The proposal on the table would have raised the single-ride fare by a quarter and left the monthly pass unchanged. Staff said the model behind it was built on the previous timetable, when two peak trains ran twelve minutes apart rather than nine, and that the difference is large enough to change the revenue estimate.")),
                .heading("The budget question"),
                .paragraph(RichText("The delay does not resolve the underlying gap. Operating costs are running roughly four percent above the adopted budget, and the reserve the board drew on last year is not available this year. Directors asked staff to bring back two options in September, one with the quarter increase and one that raises the monthly pass instead.")),
                .paragraph(RichText("Public comment on the fare proposal remains open until 28 August."))
            ],
            contentSource: .bundledFixture
        )
    }

    private static func portBerth(publishedAt: Date) -> ArticleDocument {
        let publisher = DemoPublishers.northgateJournal
        let canonical = url(publisher, "waterfront/berth-lease-negotiation")

        return ArticleDocument(
            id: ArticleID(canonicalURL: canonical),
            canonicalURL: canonical,
            publisher: publisher,
            kicker: "Waterfront",
            title: "Port Authority Weighs a Berth Lease That Could Reshape the Waterfront",
            dek: "Terms remain confidential.",
            author: "Hollis Byrne",
            publishedAt: publishedAt,
            blocks: [
                .paragraph(RichText("The port authority has entered exclusive talks over a thirty-year berth lease, according to two people briefed on the negotiation."))
            ],
            extraction: .paywalled(
                note: "Only the publisher's free excerpt is available. Broadsheet does not bypass paywalls — open the story at the publisher to read the rest."
            ),
            contentSource: .bundledFixture
        )
    }
}
