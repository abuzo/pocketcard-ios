// Synthetic acceptance fixture. Never read or transmit user data.
import Foundation

@main
struct ContractFixture {
    static func main() throws {
        for template in CardTemplate.allCases {
            var card = Card(template:template)
            card.title = "Тест 🏖️ / Фото"
            card.caption = "Подпись с кавычками: \"пример\""
            card.fields = [CardField(label:"Код",value:"0001\nВторая строка")]
            card.imageID = UUID()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(card.exportMetadata())
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([10]))
        }
    }
}
