import DeskPetCore

/// All of the cat's dialogue in one place. Short and silly by design.
enum Speech {
    static let petted = [
        "Purrrrr…", "More chin scritches pls", "You may continue.", "*happy loaf noises*",
        "I tolerate you. Fondly.", "Ah yes, the good spot.", "Prrrp!", "10/10 pets",
    ]
    static let pettedSpam = [
        "Okay okay, I'm FLUFFED.", "My fur has a limit.", "Static levels: critical.",
    ]
    static let pettedAsleep = ["zzz… *purr*…", "mrrf… fish…", "…five more naps…"]

    static let fed = [
        "Nom nom nom!", "Fish! My favourite shape.", "Chef's kiss. 🐟", "Om nom. Seconds?",
        "Delicious. 5 stars.", "This is the best day of my life (again).",
    ]
    static let tooFull = ["I'm stuffed. Truly.", "Not one more bite.", "Maybe later, chef."]

    static let played = [
        "Yarn! YARN!", "Pounce mode: activated", "I am a fierce hunter.", "Zoomies!!",
        "Again! Again!", "Got it! …did I get it?",
    ]
    static let tooTired = ["Too sleepy to play…", "Nap first, chaos later.", "My batteries say no."]

    static let sleep = ["Nap time. Do not disturb.", "Just resting my eyes…", "Loaf mode engaged."]
    static let wake = ["I'm up! I'm up!", "Did I miss snacks?", "Fully recharged!"]
    static let wokenEarly = ["Hey! I was dreaming of tuna.", "Mrrp? Already?"]
    static let asleepRefusal = ["zzz…", "*snores in cat*"]

    static let welcomeBack = ["You're back!", "Missed you! (Don't tell anyone.)", "Oh hi! I kept the desk warm."]
    static let firstHello = ["Hi! I'm your new desk buddy.", "Hello, human! Let's be friends."]
    static let recovered = ["I… forgot everything? Hi again!"]

    static func idle(for mood: PetMood) -> [String] {
        switch mood {
        case .hungry: return ["Is it snack o'clock?", "My tummy is rumbling.", "Feed me? 🥺", "I could eat a whole fish."]
        case .tired: return ["*yawn*", "So… sleepy…", "Nap? Nap.", "Running on 2% battery."]
        case .sad: return ["Play with me?", "Feeling a little lonely.", "Pet me maybe?"]
        case .happy: return ["Life is good.", "I love this desk.", "You're doing great!", "Best. Human. Ever."]
        case .content: return ["Mrrp.", "Just vibing.", "Is that a mouse? Oh, it's the cursor.", "Remember to drink water!", "Stretch break?"]
        }
    }
}
