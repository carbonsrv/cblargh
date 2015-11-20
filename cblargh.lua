-- CBlargh Server

-- Libraries
local template = require("template")
local markdown = require("3rdparty/markdown")

-- Load Settings
settings = assert(loadfile("settings.lua")())

-- IO Helper
local function readfile(path)
	local f, err = io.open(path)
	if f then
		print("Read "..path)
		local content = f:read("*a")
		f:close()
		return content
	else
		return nil, err
	end
end

-- Read template(s) into memory
local main_template = readfile("templates/main.html")
local blog_template = readfile("templates/post.html")
local fail_template = readfile("templates/fail.html")

-- Put the stuff in the kv store for eventual live reload or something.
kvstore.set("template_main", main_template)
kvstore.set("template_post", blog_template)
kvstore.set("template_fail", fail_template)
kvstore.set("title", settings.title)

-- Blog posts here!
local posts = {}
local modtimes = {}
local titles, err = io.list(settings.posts_path)
if err then
	print(err)
	os.exit(1)
end
for k, v in pairs(titles) do
	local file = settings.posts_path .. v
	print(v, "->", file)
	local src = readfile(file)
	modtimes[v] = io.modtime(file)
	posts[v] = markdown(src)
end

kvstore.set("posts", posts)
kvstore.set("modtimes", modtimes)

-- The routes
srv.Use(mw.Logger()) -- Activate logger.

srv.GET("/", mw.new(function() -- Front page
	local template = require("template")

	local res, err = template.render(kvstore.get("template_main"), {
		title=kvstore.get("title"),
		posts=kvstore.get("posts"),
		modtimes=kvstore.get("modtimes"),
		os=os
	})
	if err then
		print("Template error:", err)
	end
	content(res)
end))

srv.GET("/:postid", mw.new(function()
	local template = require("template")

	local posts = kvstore.get("posts")
	local modtimes=kvstore.get("modtimes")
	local postid = params("postid")

	local src
	if posts[postid] then -- Post exists.
		print("Post found!")
		src = kvstore.get("template_post")
	else -- Render fail template
		print("Post not found! :(")
		src = kvstore.get("template_fail")
	end

	local res, err = template.render(src, {
		postid=postid,
		post=posts[postid],
		posts=posts,
		title=kvstore.get("title"),
		modtimes=modtimes,
		os=os
	})
	if err then
		print("Template error:", err)
	end
	content(res)
end))
