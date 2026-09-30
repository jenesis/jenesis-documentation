package demo.app

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class Greeting(val name: String, val score: Int)

fun main() {
    println(Json.encodeToString(Greeting.serializer(), Greeting("Ada", 42)))
}
