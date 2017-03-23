Chapter definitions keyed by id: ("/data/chapters.json")

```json
{
	"chattanooga": {
		title: "Chattanooga",
		dataService: {
			adapter: "meetup",
			id: "Papers-We-Love-Chattanooga"
		}
	}
}
```

Meetup definitions keyed by an id (one file per chapter, ex: "/data/toronto.json"):

```json
{
	"214562152": {
		url: "http://www.meetup.com/Papers-We-Love-Toronto/events/219961100/",
		time: epoch in milliseconds
		utcOffset: in milliseconds (ex: -18000000),
		title: "John-Alan on Chord: A Scalable P2P Lookup Service for Internet Applications",
		description: "...",
		venue: {
			name: "Shopify Toronto"
			address1: "",
			address2: "",
			country: "",
			city: "",
			postalCode: "",
			lon: -79.395576, 
			lat: 43.646049
		},
		photos: [
			{
				url: "",
				width: 300,
				height: 250
			}
		]
	}
}
```

Video definitions keyed by id ("/data/videos.json"):

```json
{
	"fB2UrqbfV-4": {
		 "embedUrl": "...",
	    "published": "2017-01-24T05:56:27.000Z",
	    "title": "PwL Remote #2 - Philip Wadler on Definitional Interpreters for Higher-Order Programming Languages",
	    "description": "This talk was given on October 18th, ...",
	    "thumbnails": {
	        "default": {
	            "url": "https://i.ytimg.com/vi/fB2UrqbfV-4/default.jpg",
	            "width": 120,
	            "height": 90
	        },
	        "medium": {
	            "url": "https://i.ytimg.com/vi/fB2UrqbfV-4/mqdefault.jpg",
	            "width": 320,
	            "height": 180
	        },
	        "high": {
	            "url": "https://i.ytimg.com/vi/fB2UrqbfV-4/hqdefault.jpg",
	            "width": 480,
	            "height": 360
	        }
	    }
	}
}
```