import Foundation

struct WeatherClient {
    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable {
            let temperature: Double
            let weatherCode: Int
            let precipitation: Double
            let snowfall: Double
            let cloudCover: Double
            let isDay: Int

            enum CodingKeys: String, CodingKey {
                case temperature = "temperature_2m"
                case weatherCode = "weather_code"
                case precipitation
                case snowfall
                case cloudCover = "cloud_cover"
                case isDay = "is_day"
            }
        }

        let current: Current
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(
        latitude: Double,
        longitude: Double,
        completion: @escaping (Result<WeatherState, Error>) -> Void
    ) {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,weather_code,precipitation,rain,showers,snowfall,cloud_cover,is_day"
            ),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components.url else {
            completion(.failure(URLError(.badURL)))
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        session.dataTask(with: request) { data, response, error in
            completion(Result {
                if let error { throw error }
                guard
                    let response = response as? HTTPURLResponse,
                    response.statusCode == 200,
                    let data
                else { throw URLError(.badServerResponse) }
                return try Self.parse(data)
            })
        }.resume()
    }

    static func parse(_ data: Data) throws -> WeatherState {
        let current = try JSONDecoder().decode(OpenMeteoResponse.self, from: data).current
        return WeatherState(
            temperature: current.temperature,
            condition: weatherCondition(for: current.weatherCode),
            precipitation: current.precipitation,
            snowfall: current.snowfall,
            cloudCover: current.cloudCover,
            isDay: current.isDay == 1
        )
    }
}
