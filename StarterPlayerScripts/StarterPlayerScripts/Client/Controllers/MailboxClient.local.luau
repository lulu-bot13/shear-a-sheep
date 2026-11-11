--[[
	Every plot's Mailbox (workspace.Base.Plots.<Plot>.Mailbox.Box): its ProximityPrompt opens Roblox's built-in feedback window.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.MailboxClient
]]--

--// Services
local proximityPromptService = game:GetService("ProximityPromptService")
local socialService = game:GetService("SocialService")

--// Configs
local MAILBOX_NAME = "Mailbox"
local BOX_NAME = "Box" -- the part holding the prompt

local prompting = false

-- One listener covers every mailbox, including ones that stream in later.
proximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
	local box = prompt.Parent
	if prompting or not box or box.Name ~= BOX_NAME or not box.Parent or box.Parent.Name ~= MAILBOX_NAME then
		return
	end
	prompting = true

	local success, err = pcall(socialService.PromptFeedbackSubmissionAsync, socialService)
	if not success then
		warn("Feedback prompt failed:", err)
	end
	prompting = false
end)
