class Expert
  class << self
    def all
      [
        {
          id: 228,
          name: "Kilian Ekamp",
          expertise: [ "Coding for Non-Coders", "YouTube", "Education", "ChatGPT" ],
          twitter: "KilianEkamp",
          linkedin: "kilianekamp"
        },
        {
          id: 1,
          name: "Daniel Vassallo",
          expertise: [ "Audience Building", "Communities", "Digital Products", "Marketing", "Gumroad" ],
          twitter: "dvassallo",
          linkedin: "danielvassallo"
        },
        {
          id: 2844,
          name: "Krystian Zun",
          expertise: [ "UI/UX", "Web Design", "Branding", "Rapid Prototyping" ],
          twitter: "krystianzun",
          linkedin: "krystianzun"
        },
        {
          id: 211,
          name: "Nesters Kovalkovs",
          expertise: [ "SEO", "E-commerce", "Shopify", "Conversion Rate Optimization" ],
          twitter: "nestersk",
          linkedin: "nestersk"
        },
        {
          id: 70,
          name: "Ira Zayats",
          expertise: [ "Campfire Mods", "Ruby", "Rails" ],
          twitter: "izayats",
          linkedin: "izayats"
        },
        {
          id: 187,
          name: "Peter Askew",
          expertise: [ "Domains", "WordPress", "Job Boards", "Directories", "E-commerce", "Shopify" ],
          twitter: "searchbound",
          linkedin: "peteraskew"
        },
        {
          id: 1196,
          name: "Fernando Torres",
          expertise: [ "Amazon FBA", "Physical Products", "Manufacturing" ],
          twitter: "YvrFernando",
          linkedin: "fernandotorres91"
        },
        {
          id: 333,
          name: "Hassan Osman",
          expertise: [ "Amazon KDP", "Udemy", "Writing", "Podcasting", "Newsletters", "Beehiiv" ],
          twitter: "AuthorOnTheSide",
          linkedin: "hassano"
        },
        {
          id: 391,
          name: "Katt Risen",
          expertise: [ "No-Code", "Newsletters", "Solopreneur Tools", "Job Boards", "Directories" ],
          twitter: "kattrisen",
          linkedin: "katt-risen"
        },
        {
          id: 39,
          name: "Sairam Sundaresan",
          expertise: [ "AI Apps", "AI Research", "AI Coding", "Writing with AI" ],
          twitter: "DSaience",
          linkedin: "sairam-sundaresan"
        },
        {
          id: 343,
          name: "Greg Lim",
          expertise: [ "Amazon KDP", "Udemy", "Tech Writing" ],
          twitter: "greglim81",
          linkedin: nil
        },
        {
          id: 697,
          name: "Francesco Ambrosiano",
          expertise: [ "Google Ads", "Facebook Ads" ],
          twitter: "giftedio",
          linkedin: "francescoambrosiano"
        },
        {
          id: 1102,
          name: "Espree Devora",
          expertise: [ "Podcasting" ],
          twitter: "espreedevora",
          linkedin: "espree"
        }
      ]
    end

    def find(id)
      all.find { |expert| expert[:id] == id }
    end

    def user_ids
      all.map { |expert| expert[:id] }
    end
  end
end
