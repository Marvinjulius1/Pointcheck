import Foundation

/// Connection to the Pointcheck Supabase project (region Frankfurt).
///
/// The publishable key is meant to ship inside the app: all access is limited by the
/// row level security rules in `supabase/migrations`. Never put the service_role key
/// or the database password into the app or this repository.
enum SupabaseConfig {
    static let url = URL(string: "https://tytzuhvknfyfydziobqm.supabase.co")!
    static let publishableKey = "sb_publishable_DU-CL1j1a7iyawm3Dc5rNQ_DP7RZEn5"
}
